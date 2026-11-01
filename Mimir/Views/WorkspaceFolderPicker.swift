import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 原生 iOS 文件夹选择器（基于 UIDocumentPickerViewController）。
///
/// 严格遵守系统与 Swift 6 并发规范：
/// 1. 实现复数代理方法 didPickDocumentsAt urls，严禁使用单数方法；
/// 2. 初始化参数 asCopy: false，类型指定为 UTType.folder；
/// 3. picker.delegate 严格绑定在 context.coordinator 上防止提前释放；
/// 4. 安全权限获取与文件读取全部切到后台异步执行（Task.detached），严禁阻塞主线程。
struct WorkspaceFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: @MainActor (URL, Data, Bool) -> Void
    let onError: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 后台脱离主线程执行安全权限获取与书签生成，彻底杜绝主线程阻塞与数据竞态
    static func resolveFolderAccess(folder: URL) async -> Result<(Data, Bool), String> {
        await Task.detached(priority: .userInitiated) {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .standardizedFileURL.path
            let isAppDocument = folder.standardizedFileURL.path == documentsPath
                || folder.standardizedFileURL.path.hasPrefix(documentsPath + "/")
            let didStartAccess = folder.startAccessingSecurityScopedResource()

            guard didStartAccess || isAppDocument else {
                return .failure("无法获取所选文件夹安全权限，请选择 Mimir 文件夹或重新授权。")
            }

            do {
                let bookmark = try folder.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                return .success((bookmark, didStartAccess))
            } catch {
                if didStartAccess { folder.stopAccessingSecurityScopedResource() }
                return .failure(error.localizedDescription)
            }
        }.value
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: WorkspaceFolderPicker

        init(parent: WorkspaceFolderPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let folder = urls.first else {
                controller.dismiss(animated: true) { [weak self] in
                    self?.parent.isPresented = false
                }
                return
            }

            Task { @MainActor [weak self] in
                let result = await WorkspaceFolderPicker.resolveFolderAccess(folder: folder)
                controller.dismiss(animated: true) {
                    guard let self else { return }
                    self.parent.isPresented = false
                    switch result {
                    case .success(let (bookmark, didStartAccess)):
                        self.parent.onPick(folder, bookmark, didStartAccess)
                    case .failure(let error):
                        self.parent.onError(error)
                    }
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true) { [weak self] in
                self?.parent.isPresented = false
            }
        }
    }
}

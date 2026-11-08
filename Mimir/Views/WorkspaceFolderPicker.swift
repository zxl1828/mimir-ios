import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文件夹选择的**权限解析器**（App 内唯一的入口）。
///
/// 之前"文件夹挂载从来没成功过"的根因有两层：
/// 1. `UIDocumentPickerViewController` 被塞进 SwiftUI 的 `.sheet` 里，系统选择器
///    自己又会 dismiss 一次；代理回调里再把 `onPick` 挂在 `controller.dismiss(animated:)`
///    的 completion 上——这个 completion 在 sheet 已被 SwiftUI 拆掉时**不会执行**，
///    于是选了文件夹也毫无反应。
/// 2. 拿到的 URL 只要没有真的 start 安全作用域，后续所有读写都会静默失败。
///
/// 现在把"选文件夹"交给 SwiftUI 原生 `.fileImporter`（presentation 由系统托管，
/// 不存在双层 dismiss 竞态），这个文件只负责把 URL 变成"可长期持有的访问凭证"。
enum WorkspaceFolderAccess {

    /// 解析用户刚选中的文件夹：开启安全作用域、生成书签。
    ///
    /// - Returns: `(bookmark, scopeStarted)`；沙盒内目录不需要书签，返回 `nil`。
    static func resolve(_ folder: URL) async throws -> (bookmark: Data?, scopeStarted: Bool) {
        let outcome = try await Task.detached(priority: .userInitiated) { () throws -> (Data?, Bool) in
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .standardizedFileURL.path
            let path = folder.standardizedFileURL.path
            let isInAppDocuments = path == documentsPath || path.hasPrefix(documentsPath + "/")
            if isInAppDocuments {
                // App 自己的 Documents 天然可读写，不需要也不应该申请安全作用域。
                let bookmark = try? folder.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                return (bookmark, false)
            }

            let started = folder.startAccessingSecurityScopedResource()
            guard started else {
                throw WorkspaceAccessError.accessDenied
            }
            do {
                let bookmark = try folder.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                // 故意不 stop：作用域要一直握到用户切换工作区为止。
                return (bookmark, true)
            } catch {
                folder.stopAccessingSecurityScopedResource()
                throw error
            }
        }.value
        return (bookmark: outcome.0, scopeStarted: outcome.1)
    }
}

/// 旧的 sheet 版选择器。保留给"需要自己控制 presentation"的调用点。
///
/// 与旧实现的区别：代理回调里**立即**把 URL 交出去，不再把回调挂在 dismiss 的
/// completion 上；dismiss 交给 SwiftUI 的 binding 完成，避免二次 dismiss。
struct WorkspaceFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: @MainActor (URL) -> Void
    var onError: @MainActor (String) -> Void = { _ in }

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

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: WorkspaceFolderPicker

        init(parent: WorkspaceFolderPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let folder = urls.first else {
                parent.isPresented = false
                return
            }
            // 先交出结果，再收 UI——顺序反过来就会出现"回调丢失"。
            parent.onPick(folder)
            parent.isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

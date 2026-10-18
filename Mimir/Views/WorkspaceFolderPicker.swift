import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WorkspaceFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL, Data, Bool) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
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
                controller.dismiss(animated: true) { self.parent.isPresented = false }
                return
            }
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .standardizedFileURL.path
            let isAppDocument = folder.standardizedFileURL.path == documentsPath
                || folder.standardizedFileURL.path.hasPrefix(documentsPath + "/")
            let didStartAccess = folder.startAccessingSecurityScopedResource()
            guard didStartAccess || isAppDocument else {
                controller.dismiss(animated: true) {
                    self.parent.isPresented = false
                    self.parent.onError("无法访问所选文件夹，请重新选择并允许 Mimir 读取。")
                }
                return
            }

            do {
                let bookmark = try folder.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                controller.dismiss(animated: true) {
                    self.parent.isPresented = false
                    self.parent.onPick(folder, bookmark, didStartAccess)
                }
            } catch {
                if didStartAccess { folder.stopAccessingSecurityScopedResource() }
                controller.dismiss(animated: true) {
                    self.parent.isPresented = false
                    self.parent.onError(error.localizedDescription)
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true) { self.parent.isPresented = false }
        }
    }
}

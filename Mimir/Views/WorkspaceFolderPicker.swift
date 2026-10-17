import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WorkspaceFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL, Data) -> Void
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
                parent.isPresented = false
                return
            }
            guard folder.startAccessingSecurityScopedResource() else {
                parent.isPresented = false
                parent.onError("无法访问所选文件夹，请重新选择并允许 Mimir 读取。")
                return
            }

            do {
                let bookmark = try folder.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                parent.isPresented = false
                parent.onPick(folder, bookmark)
            } catch {
                folder.stopAccessingSecurityScopedResource()
                parent.isPresented = false
                parent.onError(error.localizedDescription)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

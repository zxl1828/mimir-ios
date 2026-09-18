import SwiftUI
import VisionKit
import UIKit

/// 文档扫描：调用系统的相机扫描器，把结果直接交给上层。
struct DocumentScannerView: UIViewControllerRepresentable {

    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            controller.dismiss(animated: true)
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            onCancel()
        }
    }
}

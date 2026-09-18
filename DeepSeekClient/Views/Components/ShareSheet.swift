import SwiftUI
import UIKit

/// 调用系统分享面板（导出文件、分享技能等场景共用）。
@MainActor
func presentShareSheet(_ items: [Any]) {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.keyWindow?.rootViewController else { return }
    var presenter = root
    while let presented = presenter.presentedViewController {
        presenter = presented
    }
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.popoverPresentationController?.sourceView = presenter.view
    controller.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 0,
        height: 0
    )
    presenter.present(controller, animated: true)
}

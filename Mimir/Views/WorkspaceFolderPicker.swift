import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文件夹选择的**权限解析器**（App 内唯一的入口）。
///
/// 之前"文件夹挂载从来没成功过"的根因有三层：
/// 1. `UIDocumentPickerViewController` 被塞进 SwiftUI 的 `.sheet` 里，系统选择器
///    自己又会 dismiss 一次；代理回调里再把 `onPick` 挂在 `controller.dismiss(animated:)`
///    的 completion 上——这个 completion 在 sheet 已被 SwiftUI 拆掉时**不会执行**，
///    于是选了文件夹也毫无反应。
/// 2. 后来改用 `.fileImporter`：它和同一层视图上的两个 `.sheet` 抢 presentation，
///    谁后挂谁生效，结果点卡片完全没反应（这正是"点击毫无响应"的原因）。
/// 3. 拿到的 URL 只要没有真的 start 安全作用域，后续所有读写都会静默失败。
///
/// 所以现在**绕开 SwiftUI 的 presentation 机制**，直接从 UIKit 最顶层的
/// view controller 上 `present` 系统选择器（见 `FolderPickerBroker`），
/// 这个文件只负责把 URL 变成"可长期持有的访问凭证"。
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

// MARK: - 系统文件夹选择器（UIKit 直连）

/// 直接向当前最顶层的 `UIViewController` 呈现系统文件夹选择器。
///
/// 为什么不用 `.fileImporter` / `.sheet`：SwiftUI 的 presentation 在同一层视图上
/// **只有一个槽位**。这个项目里同一层挂了两个 `.sheet`，于是再挂上去的选择器
/// 永远轮不到呈现——表现就是"点一下毫无响应"。绕开它以后，成败只取决于
/// 有没有一个前台 scene，与 SwiftUI 的 modifier 顺序彻底无关。
@MainActor
enum FolderPickerBroker {

    private static var retainedDelegate: FolderPickerDelegate?

    static func present(
        onPick: @escaping @MainActor (URL) -> Void,
        onCancel: @escaping @MainActor () -> Void = {},
        onError: @escaping @MainActor (String) -> Void
    ) {
        guard let presenter = topViewController() else {
            onError("找不到可以展示文件夹选择器的界面，请回到前台再试一次。")
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        let delegate = FolderPickerDelegate(onPick: onPick, onCancel: onCancel)
        picker.delegate = delegate
        // `UIDocumentPickerDelegate` 是 weak 引用，必须自己持住，否则回调还没来对象就没了。
        retainedDelegate = delegate
        presenter.present(picker, animated: true)
    }

    fileprivate static func releaseDelegate() {
        retainedDelegate = nil
    }

    /// 找当前真正在最前面的视图控制器（可能被 sheet / alert / nav / tab 包了好几层）。
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first,
              var top = window.rootViewController else { return nil }

        while true {
            if let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
                continue
            }
            if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
                top = visible
                continue
            }
            if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
                top = selected
                continue
            }
            break
        }
        return top
    }
}

@MainActor
private final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate {

    private let onPick: @MainActor (URL) -> Void
    private let onCancel: @MainActor () -> Void

    init(onPick: @escaping @MainActor (URL) -> Void, onCancel: @escaping @MainActor () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        FolderPickerBroker.releaseDelegate()
        guard let folder = urls.first else { return }
        onPick(folder)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        FolderPickerBroker.releaseDelegate()
        onCancel()
    }
}

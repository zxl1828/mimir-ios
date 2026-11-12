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
    /// 判定与副作用都在后台线程完成，结果回到主线程再记账 / 报错——
    /// 这样既不会在 `Task.detached` 里碰 `@MainActor` 的诊断台，也不阻塞 UI。
    @MainActor
    static func resolve(_ folder: URL) async throws -> (bookmark: Data?, scopeStarted: Bool) {
        enum Outcome: Sendable {
            case inSandbox(Data?)
            case scoped(Data)
            case scopeDenied
            case bookmarkFailed(String)
        }

        let outcome = try await Task.detached(priority: .userInitiated) { () throws -> Outcome in
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
                return .inSandbox(bookmark)
            }

            guard folder.startAccessingSecurityScopedResource() else {
                return .scopeDenied
            }
            do {
                let bookmark = try folder.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                // 故意不 stop：作用域要一直握到用户切换工作区为止。
                return .scoped(bookmark)
            } catch {
                folder.stopAccessingSecurityScopedResource()
                return .bookmarkFailed(error.localizedDescription)
            }
        }.value

        switch outcome {
        case .inSandbox(let bookmark):
            MountDiagnostics.shared.record("安全作用域", "App 沙盒内，无需授权")
            return (bookmark, false)
        case .scoped(let bookmark):
            MountDiagnostics.shared.record("安全作用域", "已持有 · 书签 \(bookmark.count) 字节")
            return (bookmark, true)
        case .scopeDenied:
            MountDiagnostics.shared.failure("安全作用域", "startAccessing 返回 false：\(folder.path)")
            throw WorkspaceAccessError.accessDenied
        case .bookmarkFailed(let message):
            MountDiagnostics.shared.failure("安全作用域", "生成书签失败：\(message)")
            throw WorkspaceAccessError.accessDenied
        }
    }
}

// MARK: - App 内目录（选择器彻底不可用时的兜底入口）

/// 主目录里可以被直接挂载的子目录：`Documents`（文件 App 里可见）与 `Documents/Mimir Workspace`。
/// 这条路径完全不经过系统选择器，所以一定能用——用户用「文件」App 把项目拷进 Mimir 目录即可。
enum LocalWorkspaceFolders {

    static func candidates() -> [URL] {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var results: [URL] = []
        if let children = try? fm.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory { results.append(child) }
            }
        }
        return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
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
    /// 上一次呈现出去的选择器，用于校验"到底有没有弹出来"。
    private static weak var lastPicker: UIDocumentPickerViewController?

    static func present(
        asCopy: Bool = false,
        onPick: @escaping @MainActor (URL) -> Void,
        onCancel: @escaping @MainActor () -> Void = {},
        onError: @escaping @MainActor (String) -> Void
    ) {
        let diagnostics = MountDiagnostics.shared
        diagnostics.begin(asCopy ? "导入副本" : "选择文件夹")

        guard let presenter = topViewController() else {
            diagnostics.failure("查找宿主界面", "没有拿到前台 scene 的 window / rootViewController")
            onError("找不到可以展示文件夹选择器的界面，请回到前台再试一次。")
            return
        }
        diagnostics.record("查找宿主界面", String(describing: type(of: presenter)))

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: asCopy)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        let delegate = FolderPickerDelegate(onPick: onPick, onCancel: onCancel)
        picker.delegate = delegate
        // `UIDocumentPickerDelegate` 是 weak 引用，必须自己持住，否则回调还没来对象就没了。
        retainedDelegate = delegate
        lastPicker = picker

        // 呈现前先把已经在弹的东西收掉：菜单 / 弹窗 / 半屏 sheet 期间 present 会被系统直接拒绝，
        // 而且不会抛错——这正是"点了没反应"的经典成因。
        var needsDelay = false
        if let presented = presenter.presentedViewController {
            diagnostics.record("收起已有弹窗", String(describing: type(of: presented)))
            presented.dismiss(animated: false)
            needsDelay = true
        }
        // 从 contextMenu 里点进来的那一刻，菜单本身还在收；直接 present 会被系统吞掉。
        // 统一等一个极短的空档再呈现，代价是 0.2 秒，换来的是"点了就一定有反应"。
        needsDelay = needsDelay || presenter.view.window == nil

        let presentNow: @MainActor () -> Void = {
            guard lastPicker === picker else { return }
            guard presenter.presentedViewController == nil else {
                diagnostics.failure("呈现选择器", "宿主正忙（已有其它弹窗未收起）")
                releaseDelegate()
                onError("有其它弹窗还没收起，请稍后再点一次。")
                return
            }
            presenter.present(picker, animated: true)
        }

        if needsDelay {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                presentNow()
            }
        } else {
            presentNow()
        }

        // 0.7 秒后校验：presentingViewController 为空就说明系统没接受这次呈现。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard lastPicker === picker else { return }
            if picker.presentingViewController == nil {
                diagnostics.failure("呈现选择器", "系统拒绝了 present（presentation 被占用或正在进行转场）")
                releaseDelegate()
                onError("系统选择器没有弹出来。请退到首页、等一秒再点「更换文件夹」；或者用「导入副本」。")
            } else {
                diagnostics.record("呈现选择器", "已显示")
            }
        }
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
        MountDiagnostics.shared.record("选择器回调", urls.first?.path ?? "空 URL")
        guard let folder = urls.first else { return }
        onPick(folder)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        FolderPickerBroker.releaseDelegate()
        MountDiagnostics.shared.record("选择器回调", "用户取消")
        onCancel()
    }
}


// MARK: - 挂载诊断面板

/// 把挂载链路的每一步摆出来：点了哪一步、回调有没有回来、授权有没有拿到。
/// 用户把这张表截图发回来，就能直接定位是"没弹出来"还是"读不到文件"。
struct MountDiagnosticsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics = MountDiagnostics.shared
    @State private var localFolders: [URL] = []
    var onPickLocalFolder: (URL) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            List {
                Section("链路") {
                    if diagnostics.steps.isEmpty {
                        Text("还没有挂载记录。点一次「更换文件夹」再回来看。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(diagnostics.steps) { step in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(step.isFailure ? Color.red : Color.green)
                                        .frame(width: 6, height: 6)
                                    Text(step.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Spacer()
                                    Text(step.at, format: .dateTime.hour().minute().second())
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Text(step.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("App 内目录（不经过系统选择器）") {
                    if localFolders.isEmpty {
                        Text("Documents 里还没有子目录。用「文件」App 打开 Mimir 文件夹，把项目拷进来就会出现。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(localFolders, id: \.path) { folder in
                            Button {
                                onPickLocalFolder(folder)
                                dismiss()
                            } label: {
                                Label(folder.lastPathComponent, systemImage: "folder")
                                    .font(.system(size: 13))
                            }
                        }
                    }
                }
            }
            .navigationTitle("挂载诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("清空") { diagnostics.reset() }
                }
            }
            .task { localFolders = LocalWorkspaceFolders.candidates() }
        }
    }
}
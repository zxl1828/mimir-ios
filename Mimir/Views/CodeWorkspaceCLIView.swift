import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 同一层视图只保留一个 presentation 槽位，两个弹层用枚举合并。
private enum CodeWorkspaceSheet: String, Identifiable {
    case sourceFile
    case github

    var id: String { rawValue }
}

/// Phone-first source editor and coding agent for a user-selected local project folder.
struct CodeWorkspaceCLIView: View {
    @Environment(\.dismiss) private var dismiss

    /// 由首页 Push 进入时为 true：顶栏左侧显示返回键。
    private let showsBackButton: Bool

    init(showsBackButton: Bool = false) {
        self.showsBackButton = showsBackButton
    }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(\.openURL) private var openURL
    @State private var workspace = WorkspaceManager.shared
    @State private var agent = CodeWorkspaceAgent()
    @State private var settings = AppSettings()
    @State private var activeSheet: CodeWorkspaceSheet?
    @State private var showMountDiagnostics = false
    @State private var isLoadingWorkspace = false
    @State private var editorExpanded = false
    @State private var isKeyboardVisible = false
    @State private var workspaceLoadError: String?
    @State private var draft = ""
    @State private var saveState = "已保存"
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmRemoteBuild = false
    @State private var repositoryDraft = ""
    @State private var tokenDraft = ""
    @State private var isBindingGitHub = false
    @State private var githubBindingError: String?
    @State private var isBuilding = false
    @State private var buildMessage = ""
    @State private var buildError: String?
    @State private var buildResult: GitHubBuildResult?
    @FocusState private var composerFocused: Bool

    // MARK: - Task 2: Voice-to-AST Diff Engine

    private let codeTabBarClearance: CGFloat = 66 + 12 + 28

    private var composerBottomClearance: CGFloat {
        isKeyboardVisible ? 10 : codeTabBarClearance
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                header
                if isLoadingWorkspace {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在读取项目文件…")
                    }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let workspaceLoadError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(workspaceLoadError)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("关闭") { self.workspaceLoadError = nil }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                editorPanel(height: editorExpanded ? min(geometry.size.height * 0.62, 560) : min(max(geometry.size.height * 0.44, 230), 410))
                if !buildMessage.isEmpty { buildStatusBar }
                agentPanel
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, composerBottomClearance)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        // 只留**一个** presentation 槽位：两个 `.sheet` 合并成 `.sheet(item:)`。
        // 之前 `.fileImporter` 和两个 `.sheet` 挂在同一层视图上，SwiftUI 只有一个
        // presentation 槽位，先挂的会被后挂的顶掉——表现为"点文件夹卡片毫无响应"。
        .sheet(isPresented: $showMountDiagnostics) {
            MountDiagnosticsView { folder in
                Task { await adoptFolder(folder) }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sourceFile:
                sourceFilePicker
            case .github:
                githubSettingsSheet
            }
        }
        .confirmationDialog("上传项目并编译？", isPresented: $confirmRemoteBuild, titleVisibility: .visible) {
            Button("上传并构建", role: .destructive) {
                Task { await buildSelectedProject() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将以 @\(settings.githubAccountLogin) 身份上传 \(uploadFileCount) 个文件（\(ByteCountFormatter.string(fromByteCount: uploadBytes, countStyle: .file))）到 \(settings.githubRepository) 的临时分支。公开仓库中的源码在构建期间可被他人查看；Actions 构建产物保留 30 天，临时分支会在构建结束后删除。")
        }
        .alert("构建失败", isPresented: Binding(
            get: { buildError != nil },
            set: { if !$0 { buildError = nil } }
        )) {
            Button("好", role: .cancel) { buildError = nil }
        } message: {
            Text(buildError ?? "")
        }
        .alert("无法保存文件", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if TabNavigationCoordinator.shared.selectedTab == .code || (TabNavigationCoordinator.shared.selectedTab == .home && TabNavigationCoordinator.shared.topMode == .code) {
                    await workspace.refreshCurrentCodeFile()
                }
            }
        }
        .onDisappear {
            saveTask?.cancel()
            Task { await persistCurrentFile() }
        }
    }

    /// 打开系统文件夹选择器。
    ///
    /// 直接走 `FolderPickerBroker`（UIKit 顶层 VC），不用 `.fileImporter`：
    /// 这个视图同层还有 `.sheet(item:)` 和两个 `.alert`，SwiftUI 的 presentation
    /// 槽位会被抢占，导致点卡片完全没有反应。
    private func presentFolderPicker(asCopy: Bool = false) {
        Haptics.selectionChanged()
        FolderPickerBroker.present(
            asCopy: asCopy,
            onPick: { folder in
                Task {
                    if asCopy {
                        await importWorkspaceCopy(folder)
                    } else {
                        await adoptFolder(folder)
                    }
                }
            },
            onCancel: {
                saveState = "已取消选择"
            },
            onError: { message in
                workspaceLoadError = message
            }
        )
    }

    /// 接管用户选中的文件夹：先按"安全作用域书签"挂载，失败则给出可执行的替代路径。
    private func adoptFolder(_ folder: URL) async {
        isLoadingWorkspace = true
        workspaceLoadError = nil
        defer { isLoadingWorkspace = false }
        do {
            let access = try await WorkspaceFolderAccess.resolve(folder)
            try await workspace.mountFolder(
                url: folder,
                bookmarkData: access.bookmark,
                securityScopeAlreadyStarted: access.scopeStarted
            )
            workspace.selectCodeFile(workspace.sourceFiles.first)
            saveState = "已载入工作区"
        } catch {
            workspace.noteMountFailure(error)
            workspaceLoadError = "无法读取该文件夹：\(error.localizedDescription)。可以点「导入副本」把整个目录复制进 App，权限不会再失效。"
        }
    }

    /// 兜底：整份复制进沙盒后挂载。
    ///
    /// `asCopy: true` 的选择器已经由系统把目录复制进容器，这时直接挂载即可；
    /// 只有系统把原始 URL 交回来（外部目录）时才需要自己再复制一份。
    private func importWorkspaceCopy(_ folder: URL) async {
        isLoadingWorkspace = true
        workspaceLoadError = nil
        defer { isLoadingWorkspace = false }
        do {
            if workspace.isInAppDocuments(folder) {
                try await workspace.mountFolder(url: folder, bookmarkData: nil, securityScopeAlreadyStarted: false)
            } else {
                _ = try await workspace.mountSandboxCopy(of: folder)
            }
            workspace.selectCodeFile(workspace.sourceFiles.first)
            saveState = "已导入副本"
        } catch {
            workspace.noteMountFailure(error)
            workspaceLoadError = "导入副本失败：\(error.localizedDescription)"
        }
    }

    private func loadWorkspace(from folder: URL, bookmarkData: Data? = nil, securityScopeAlreadyStarted: Bool = false) {
        isLoadingWorkspace = true
        workspaceLoadError = nil
        Task {
            defer { isLoadingWorkspace = false }
            do {
                try await workspace.mountFolder(
                    url: folder,
                    bookmarkData: bookmarkData,
                    securityScopeAlreadyStarted: securityScopeAlreadyStarted
                )
                workspace.selectCodeFile(workspace.sourceFiles.first)
                saveState = "已载入工作区"
            } catch {
                workspace.noteMountFailure(error)
                workspaceLoadError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                if showsBackButton {
                    Button {
                        Haptics.impact(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppUI.textTitle(scheme: scheme))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(AppUI.consolePanel(scheme: scheme)))
                            .overlay(Circle().strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 0.5))
                    }
                    .buttonStyle(StaticButtonFeedbackStyle())
                    .accessibilityLabel("返回")
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("CODE / LIVE WORKSPACE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("代码工坊")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Circle()
                        .fill(agent.isWorking || isLoadingWorkspace ? accent : Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: accent.opacity(agent.isWorking || isLoadingWorkspace ? 0.65 : 0), radius: 5)
                    Text(isLoadingWorkspace ? "读取项目" : (agent.isWorking ? "处理中" : "就绪"))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(accent.opacity(scheme == .dark ? 0.15 : 0.09)))
            }

            workspaceCard

            HStack(spacing: 8) {
                Button {
                    presentFolderPicker()
                } label: {
                    Label("更换文件夹", systemImage: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .liquidGlass(.regular.tint(accent.opacity(0.12)), in: .rect(cornerRadius: 13))
                        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1) }
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .disabled(isLoadingWorkspace)
                .accessibilityHint("从文件 App 中选择要编辑的项目目录")

                Button {
                    presentFolderPicker(asCopy: true)
                } label: {
                    Label("导入副本", systemImage: "square.and.arrow.down.on.square")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .liquidGlass(.regular, in: .rect(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1) }
                    }
                    .buttonStyle(StaticButtonFeedbackStyle())
                    .disabled(isLoadingWorkspace)
                    .accessibilityHint("把这个目录整份复制进 App，重启后依然可用")

                Button {
                    Task { await workspace.refreshActiveWorkspace() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                        .liquidGlass(.regular, in: .circle)
                        .overlay { Circle().strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1) }
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .accessibilityLabel("重新扫描工作区")

                Spacer(minLength: 0)

                Button {
                    activeSheet = .sourceFile
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                        .liquidGlass(.regular, in: .circle)
                        .overlay { Circle().strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1) }
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .accessibilityLabel("选择源码文件")

                Button(action: beginRemoteBuild) {
                    HStack(spacing: 5) {
                        Image(systemName: isBuilding ? "hourglass" : "hammer.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isBuilding ? "构建中" : "编译")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(accent))
                    .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.42), lineWidth: 0.8) }
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .disabled(isBuilding || workspace.activeWorkspaceURL == nil)
                .accessibilityLabel("通过 GitHub Actions 编译此项目")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .softGlassCard(cornerRadius: 18)
    }

    /// 工作区卡片：文件夹图标 + 名称 + 真实路径 + 挂载状态点。
    ///
    /// 视觉参照 DeepSeek harness 首页那张项目卡：一整个可点的玻璃矩形，
    /// 主行是项目名，副行是等宽字体的真实路径，右侧一个状态点收尾。
    private var workspaceCard: some View {
        let state = workspace.mountState
        return Button {
            Haptics.selectionChanged()
            presentFolderPicker()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(workspaceBlue.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(workspaceBlue)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                    Text(state.detail)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                mountBadge(state)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme).opacity(0.7))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.75))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel("工作区 \(state.title)")
        .accessibilityHint(state.detail)
        .contextMenu {
            Button {
                showMountDiagnostics = true
            } label: {
                Label("挂载诊断", systemImage: "stethoscope")
            }
            Button {
                presentFolderPicker(asCopy: true)
            } label: {
                Label("导入副本到 App", systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                presentFolderPicker()
            } label: {
                Label("重新选择文件夹", systemImage: "folder.badge.plus")
            }
        }
    }

    private var workspaceBlue: Color {
        AppUI.consoleSignal
    }

    @ViewBuilder
    private func mountBadge(_ state: WorkspaceMountState) -> some View {
        HStack(spacing: 5) {
            switch state {
            case .mounted:
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("已挂载")
            case .mounting:
                ProgressView().controlSize(.mini)
                Text("挂载中")
            case .failed:
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("失败")
            case .idle:
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                Text("未挂载")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
    }

    private var buildStatusBar: some View {
        HStack(spacing: 8) {
            if isBuilding { ProgressView().controlSize(.mini) }
            Image(systemName: buildResult == nil ? "arrow.up.forward.app" : "checkmark.icloud")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(buildMessage)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let result = buildResult {
                Link(destination: result.runURL) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .accessibilityLabel("打开 GitHub Actions 构建记录")
            }
        }
        .padding(.horizontal, 10)
    }

    private func editorPanel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green.opacity(workspace.currentActiveCodeFile == nil ? 0.35 : 0.92))
                    .frame(width: 5, height: 5)
                Text("LIVE SOURCE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(workspace.currentActiveCodeFile?.fileExtension.uppercased() ?? "PROJECT")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                Spacer(minLength: 4)
                Text(saveState)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .lineLimit(1)
                Button {
                    Task {
                        saveState = "正在扫描"
                        await workspace.refreshActiveWorkspace()
                        if let file = workspace.currentActiveCodeFile {
                            workspace.selectCodeFile(file)
                        }
                        saveState = "已重新载入"
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .accessibilityLabel("重新载入文件")
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppUI.refractionEdge(accent, scheme: scheme).opacity(0.6)).frame(height: 0.6)
            }

            HStack(spacing: 8) {
                Image(systemName: workspace.currentActiveCodeFile?.systemIcon ?? "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(workspace.currentActiveCodeFile.flatMap(workspace.relativePath(for:)) ?? "未选择源码")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            if workspace.currentActiveCodeFile != nil {
                TextEditor(text: Binding(
                    get: { workspace.currentCodeContent },
                    set: { updateCode($0) }
                ))
                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                .foregroundStyle(AppUI.textTitle(scheme: scheme))
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color(hex: "241936").opacity(0.55) : Color.white.opacity(0.58))
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(accent)
                    Text(workspace.activeWorkspaceURL == nil ? "先选择手机上的项目文件夹" : "这个文件夹里还没有可编辑的源码")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Button("选择文件夹") { presentFolderPicker() }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? Color(hex: "241936").opacity(0.55) : Color.white.opacity(0.58))
            }
        }
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: accent.opacity(scheme == .dark ? 0.13 : 0.09), radius: 20, y: 9)
    }

    private var agentPanel: some View {
        VStack(spacing: 8) {
            liveSourceStrip
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if agent.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mimir Code")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                                Text("和平时对话一样描述要做的事，Agent 会在当前文件夹里查找、读取并保存代码；改完的源码会直接出现在上方的编辑器里。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        }
                        ForEach(agent.turns) { turn in
                            turnBubble(turn)
                                .id(turn.id)
                        }
                        if let runID = agent.runID {
                            FileEditSummaryCard(runID: runID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .correctedSoftFadeMask(topFade: 8, bottomFade: 14)
                .onChange(of: agent.turns.count) { _, _ in
                    guard let last = agent.turns.last else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: agent.isWorking) { _, working in
                    guard !working, let last = agent.turns.last else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 4) {
                TextField("让 Agent 检查或修改代码…", text: $draft, axis: .vertical)
                    .font(.system(size: 13.5))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitDraft() }
                    .padding(.leading, 12)
                    .padding(.vertical, 10)

                Button {
                    if agent.isWorking {
                        agent.cancel()
                        Haptics.impact(.light)
                    } else {
                        submitDraft()
                    }
                } label: {
                    Image(systemName: agent.isWorking ? "square.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(agent.isWorking ? AppUI.textTitle(scheme: scheme) : Color.white)
                        .frame(width: 34, height: 32)
                        .nativeGlass(
                            AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)),
                            tint: agent.isWorking ? nil : accent.opacity(0.55)
                        )
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .disabled(!agent.isWorking && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(agent.isWorking ? "停止生成" : "发送给代码 Agent")
            }
            .padding(.horizontal, 6)
            .nativeGlassRect(cornerRadius: 22)
        }
        .frame(maxHeight: .infinity)
    }

    /// 编辑器里正在显示的那份源码，就是 Agent 刚改出来的那份。
    @ViewBuilder
    private var liveSourceStrip: some View {
        if let path = agent.liveFilePath {
            Button {
                Haptics.selectionChanged()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { editorExpanded = true }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.78, blue: 0.46))
                        .frame(width: 6, height: 6)
                    Text("实时源码")
                        .font(AppUI.mono(10, weight: .medium))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    Text(path)
                        .font(AppUI.mono(10.5, weight: .medium))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("\(agent.liveContent.utf8.count) B")
                        .font(AppUI.mono(9.5))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeGlassRect(cornerRadius: 12, interactive: false)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("实时源码 \(path)")
        }
    }

    @ViewBuilder
    private func turnBubble(_ turn: CodeAgentTurn) -> some View {
        switch turn.kind {
        case .user:
            Text(turn.text)
                .font(.system(size: 13))
                .foregroundStyle(AppUI.label)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    scheme == .dark ? Color.white.opacity(0.09) : Color(red: 0.945, green: 0.952, blue: 0.970),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !turn.reasoning.isEmpty {
                    CodeReasoningRow(text: turn.reasoning, isStreaming: turn.isStreaming)
                }
                if turn.text.isEmpty {
                    if turn.isStreaming {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("正在推演…")
                                .font(.system(size: 12))
                                .foregroundStyle(AppUI.textCaption(scheme: scheme))
                        }
                    }
                } else {
                    MarkdownText(raw: turn.text, isStreaming: turn.isStreaming)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .activity:
            HStack(spacing: 5) {
                Image(systemName: turn.didWriteFile ? "square.and.pencil" : "terminal")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(turn.didWriteFile ? accent : AppUI.textCaption(scheme: scheme))
                Text(turn.text)
                    .font(AppUI.mono(10.5))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceFilePicker: some View {
        NavigationStack {
            List(workspace.sourceFiles) { file in
                Button {
                    Task {
                        await persistCurrentFile()
                        workspace.selectCodeFile(file)
                        saveState = "已载入"
            activeSheet = nil
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: file.systemIcon).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name).foregroundStyle(.primary)
                            Text(workspace.relativePath(for: file) ?? file.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if workspace.currentActiveCodeFile?.id == file.id {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                        }
                    }
                }
            }
            .navigationTitle("源码文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var githubSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("你的 GitHub 仓库") {
                    TextField("owner/repository", text: $repositoryDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                    SecureField("你的 Fine-grained personal access token", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if settings.githubTokenIsConfigured {
                        if settings.githubAccountLogin.isEmpty {
                            Label("令牌尚未验证，请重新绑定", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        } else {
                            Label("已绑定 GitHub 账号 @\(settings.githubAccountLogin)", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
                        Button("解除 GitHub 账号绑定", role: .destructive) {
                            unbindGitHubAccount()
                        }
                    }
                    if let githubBindingError {
                        Label(githubBindingError, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("保存前会向 GitHub 验证令牌并显示账号。令牌仅保存在本机钥匙串；需要目标仓库 Contents 与 Actions 读写权限，默认分支需包含 .github/workflows/build-ipa.yml。")
                        .font(.system(size: 12))
                    Text("构建会将所选文件夹写入你绑定仓库的独立临时分支。公开仓库会公开这些源文件；构建结束后分支自动删除，GitHub Actions 产物保留 30 天。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Link("创建仓库访问令牌", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        .font(.system(size: 12, weight: .semibold))
                } header: {
                    Text("构建访问")
                }
            }
            .navigationTitle("GitHub 构建绑定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                Button("取消") { activeSheet = nil }
                        .disabled(isBindingGitHub)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isBindingGitHub ? "验证中…" : "验证并绑定") {
                        Task { await saveGitHubSettings() }
                    }
                    .disabled(isBindingGitHub
                        || repositoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !settings.githubTokenIsConfigured))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isBindingGitHub)
        .onAppear {
            repositoryDraft = settings.githubRepository
            tokenDraft = ""
        }
    }

    private var uploadFileCount: Int {
        uploadFiles.count
    }

    private var uploadBytes: Int64 {
        uploadFiles.reduce(0) { $0 + $1.size }
    }

    private var uploadFiles: [WorkspaceFileItem] {
        let excludedDirectories: Set<String> = [".git", "Build", ".build", "DerivedData", "node_modules", "Pods", "Carthage"]
        return workspace.allFiles.filter { item in
            guard !item.isDirectory,
                  item.url != nil,
                  let path = workspace.relativePath(for: item) else { return false }
            return !path.split(separator: "/").contains { excludedDirectories.contains(String($0)) }
        }
    }

    private func beginRemoteBuild() {
        guard !settings.githubRepository.isEmpty,
              !settings.githubAccountLogin.isEmpty,
              settings.githubTokenIsConfigured else {
                    activeSheet = .github
            return
        }
        confirmRemoteBuild = true
    }

    private func saveGitHubSettings() async {
        guard !isBindingGitHub else { return }
        isBindingGitHub = true
        githubBindingError = nil
        defer { isBindingGitHub = false }

        let repository = repositoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? settings.resolvedGitHubToken
            : tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy({ $0.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil }),
              !token.isEmpty else {
            githubBindingError = "请输入有效的 owner/repository 和个人访问令牌。"
            return
        }

        do {
            let login = try await GitHubActionsBuildService.authenticatedLogin(token: token)
            if !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try settings.storeGitHubToken(token)
            }
            settings.githubAccountLogin = login
            settings.githubRepository = repository
            activeSheet = nil
        } catch {
            githubBindingError = error.localizedDescription
        }
    }

    private func unbindGitHubAccount() {
        do {
            try settings.storeGitHubToken("")
            tokenDraft = ""
            repositoryDraft = ""
            githubBindingError = nil
        } catch {
            githubBindingError = error.localizedDescription
        }
    }

    private func buildSelectedProject() async {
        isBuilding = true
        buildResult = nil
        buildMessage = "正在以 @\(settings.githubAccountLogin) 身份上传到 \(settings.githubRepository)…"
        defer { isBuilding = false }
        let repository = settings.githubRepository
        let accountLogin = settings.githubAccountLogin
        let token = settings.resolvedGitHubToken

        do {
            let result = try await GitHubActionsBuildService.dispatch(
                workspace: workspace,
                repository: repository,
                expectedAccountLogin: accountLogin,
                token: token
            )
            buildResult = result
            let privacy = result.isPrivateRepository ? "私有仓库" : "公开仓库"
            buildMessage = "已验证 @\(result.accountLogin)，上传 \(result.fileCount) 个文件到 \(result.repository)（\(privacy)），等待 Xcode 构建…"
            guard let runID = result.runID else { return }

            for _ in 0..<270 {
                try await Task.sleep(for: .seconds(10))
                let status = try await GitHubActionsBuildService.status(
                    runID: runID,
                    repository: repository,
                    token: token
                )
                if status.status == "completed" {
                    if status.conclusion == "success" {
                        buildMessage = "IPA 构建成功。打开 Actions 页面下载产物。"
                    } else {
                        buildMessage = "构建结束：\(status.conclusion ?? "未知状态")。打开 Actions 查看日志。"
                    }
                    break
                }
                if status.status == "queued" {
                    buildMessage = "Xcode 构建排队中…"
                } else if let activeStep = status.activeStep {
                    buildMessage = "正在执行：\(activeStep)"
                } else {
                    buildMessage = "Xcode 正在编译所选项目…"
                }
            }
        } catch {
            buildError = error.localizedDescription
            buildMessage = "构建未启动"
        }
    }

    private func updateCode(_ content: String) {
        workspace.currentCodeContent = content
        saveState = "未保存"
        saveTask?.cancel()
        guard let file = workspace.currentActiveCodeFile else { return }
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await workspace.saveFileContent(item: file, newContent: content)
                saveState = "已保存"
            } catch {
                saveError = error.localizedDescription
                saveState = "保存失败"
            }
        }
    }

    private func persistCurrentFile() async {
        saveTask?.cancel()
        guard let file = workspace.currentActiveCodeFile,
              workspace.currentCodeContent != "" else { return }
        do {
            try await workspace.saveFileContent(item: file, newContent: workspace.currentCodeContent)
            saveState = "已保存"
        } catch {
            saveError = error.localizedDescription
            saveState = "保存失败"
        }
    }

    private func submitDraft() {
        let prompt = draft
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        composerFocused = false
        Task {
            await persistCurrentFile()
            await agent.send(prompt, workspace: workspace, settings: settings)
        }
    }


}


// MARK: - 代码页的思考折叠行

/// 与主对话里的"思考"折叠行同一套观感：默认只显示开头，点开看全程推演。
private struct CodeReasoningRow: View {

    let text: String
    let isStreaming: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    private var summary: String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = String(flat.prefix(40))
        return head.isEmpty ? "正在思考…" : "· " + head
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .semibold))
                    Text("思考")
                        .font(.system(size: 11, weight: .medium))
                    Text(summary)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(AppUI.textCaption(scheme: scheme).opacity(0.35))
                            .frame(width: 1.5)
                    }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
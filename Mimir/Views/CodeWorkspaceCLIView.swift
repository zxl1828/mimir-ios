import SwiftUI
import UniformTypeIdentifiers

/// Phone-first source editor and coding agent for a user-selected local project folder.
struct CodeWorkspaceCLIView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(\.openURL) private var openURL
    @State private var workspace = WorkspaceManager.shared
    @State private var agent = CodeWorkspaceAgent()
    @State private var settings = AppSettings()
    @State private var showFolderImporter = false
    @State private var showFilePicker = false
    @State private var draft = ""
    @State private var saveState = "已保存"
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var showGitHubSettings = false
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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                header
                editorPanel(height: min(max(geometry.size.height * 0.44, 230), 410))
                if !buildMessage.isEmpty { buildStatusBar }
                agentPanel
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                AppUI.ambientBackground(scheme: scheme).ignoresSafeArea()
            }
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let folder = urls.first {
                workspace.mountFolder(url: folder)
                workspace.selectCodeFile(workspace.sourceFiles.first)
                saveState = "已载入工作区"
            }
        }
        .sheet(isPresented: $showFilePicker) {
            sourceFilePicker
        }
        .sheet(isPresented: $showGitHubSettings) {
            githubSettingsSheet
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
                workspace.refreshCurrentCodeFile()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            persistCurrentFile()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("代码 Agent")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    Circle()
                        .fill(agent.isWorking ? accent : Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: accent.opacity(agent.isWorking ? 0.7 : 0), radius: 5)
                    Text(agent.isWorking ? "处理中" : "就绪")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                }
                Text(workspace.activeWorkspaceURL?.lastPathComponent ?? "选择一个项目文件夹")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                showFolderImporter = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .liquidGlass(.regular, in: .circle)
                    .overlay { Circle().strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1) }
            }
            .buttonStyle(PhysicalElasticCircleButtonStyle())
            .accessibilityLabel("选择项目文件夹")

            Button {
                showFilePicker = true
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .liquidGlass(.regular, in: .circle)
                    .overlay { Circle().strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1) }
            }
            .buttonStyle(PhysicalElasticCircleButtonStyle())
            .accessibilityLabel("选择源码文件")

            Button(action: beginRemoteBuild) {
                HStack(spacing: 5) {
                    Image(systemName: isBuilding ? "hourglass" : "hammer.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isBuilding ? "构建中" : "编译")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(Capsule().fill(accent))
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.42), lineWidth: 0.8) }
            }
            .buttonStyle(PhysicalElasticCapsuleButtonStyle())
            .disabled(isBuilding || workspace.activeWorkspaceURL == nil)
            .accessibilityLabel("通过 GitHub Actions 编译此项目")
        }
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
                Image(systemName: workspace.currentActiveCodeFile?.systemIcon ?? "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(workspace.currentActiveCodeFile.flatMap(workspace.relativePath(for:)) ?? "未选择源码")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                Text(saveState)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .lineLimit(1)
                Button {
                    workspace.refreshActiveWorkspace()
                    if let file = workspace.currentActiveCodeFile {
                        workspace.selectCodeFile(file)
                        saveState = "已重新载入"
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle(scale: 0.92))
                .accessibilityLabel("重新载入文件")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppUI.refractionEdge(accent, scheme: scheme).opacity(0.6)).frame(height: 0.6)
            }

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
                .background(scheme == .dark ? AppUI.baseDarkDeepPurple.opacity(0.72) : AppUI.baseLightWhite.opacity(0.88))
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(accent)
                    Text(workspace.activeWorkspaceURL == nil ? "先选择手机上的项目文件夹" : "这个文件夹里还没有可编辑的源码")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    Button("选择文件夹") { showFolderImporter = true }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? AppUI.baseDarkDeepPurple.opacity(0.72) : AppUI.baseLightWhite.opacity(0.88))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var agentPanel: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if agent.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mimir Code")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                                Text("描述要检查或修改的内容，Agent 会在当前文件夹中查找、读取并保存代码。")
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
            }

            HStack(spacing: 8) {
                TextField("让 Agent 检查或修改代码…", text: $draft, axis: .vertical)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitDraft() }
                    .padding(.leading, 12)
                    .padding(.vertical, 10)

                Button(action: submitDraft) {
                    Image(systemName: agent.isWorking ? "ellipsis" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(accent))
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle(scale: 0.92))
                .disabled(agent.isWorking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.trailing, 5)
                .accessibilityLabel("发送给代码 Agent")
            }
            .liquidGlass(.regular, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func turnBubble(_ turn: CodeAgentTurn) -> some View {
        switch turn.kind {
        case .user:
            Text(turn.text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            Text(turn.text.isEmpty ? "正在思考…" : turn.text)
                .font(.system(size: 12.5))
                .foregroundStyle(AppUI.textTitle(scheme: scheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .activity:
            Label(turn.text, systemImage: "terminal")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppUI.textCaption(scheme: scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceFilePicker: some View {
        NavigationStack {
            List(workspace.sourceFiles) { file in
                Button {
                    persistCurrentFile()
                    workspace.selectCodeFile(file)
                    saveState = "已载入"
                    showFilePicker = false
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
                    Button("完成") { showFilePicker = false }
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
                    Button("取消") { showGitHubSettings = false }
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
            showGitHubSettings = true
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
            showGitHubSettings = false
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
                try workspace.saveFileContent(item: file, newContent: content)
                saveState = "已保存"
            } catch {
                saveError = error.localizedDescription
                saveState = "保存失败"
            }
        }
    }

    private func persistCurrentFile() {
        saveTask?.cancel()
        guard let file = workspace.currentActiveCodeFile,
              workspace.currentCodeContent != "" else { return }
        do {
            try workspace.saveFileContent(item: file, newContent: workspace.currentCodeContent)
            saveState = "已保存"
        } catch {
            saveError = error.localizedDescription
            saveState = "保存失败"
        }
    }

    private func submitDraft() {
        let prompt = draft
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        persistCurrentFile()
        draft = ""
        composerFocused = false
        Task { await agent.send(prompt, workspace: workspace, settings: settings) }
    }
}

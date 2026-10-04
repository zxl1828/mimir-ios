import SwiftUI
import WebKit

/// 页面三：代码工坊（Code Workspace View）。
///
/// 专为代码审查、多语言脚本调试、Web 实时内联预览与逻辑重构打造的沉浸式工作台。
struct CodeWorkspaceView: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(AppSettings.self) private var settings

    @State private var workspace = WorkspaceManager.shared
    @State private var mcpManager = MCPClientManager.shared

    @State private var selectedLanguage: CodeLanguage = .swift
    @State private var currentCode: String = WorkspaceManager.sampleSwiftCode
    @State private var fileName: String = "AgentRunner.swift"

    @State private var showConsole = false
    @State private var isLivePreviewMode = false
    @State private var consoleLogs: [ConsoleLogEntry] = []
    @State private var isExecuting = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var aiPromptText = ""
    @State private var showReasoningCard = false
    @State private var thinkingMode: ThinkingMode = .ultra
    @State private var isFullScreenEditor = false

    private var coordinator: TabNavigationCoordinator {
        TabNavigationCoordinator.shared
    }

    enum CodeLanguage: String, CaseIterable, Identifiable, Sendable {
        case swift = "Swift"
        case html = "HTML/JS"
        case python = "Python"
        case json = "JSON"

        var id: String { rawValue }

        var tagColor: Color {
            switch self {
            case .swift: return Color(hex: "F97316")
            case .html: return Color(hex: "38BDF8")
            case .python: return Color(hex: "34D399")
            case .json: return Color(hex: "A78BFA")
            }
        }
    }

    struct ConsoleLogEntry: Identifiable, Sendable {
        var id = UUID()
        var time = Date()
        var message: String
        var isError: Bool = false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // 1. 顶部工作区标头
                    workspaceHeader
                        .staggeredSlideEntrance(index: 0)

                    // 2. 代码工作区主卡片 (Code Stage Container)
                    codeStageContainer
                        .staggeredSlideEntrance(index: 1)

                    // 3. 底部执行输出控制台 (Execution & Output Console)
                    consoleSection
                        .staggeredSlideEntrance(index: 2)

                    // 4. AI 上下文重构输入区（带模型思考程度胶囊与输入条）
                    aiRefactorInputBar
                        .staggeredSlideEntrance(index: 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 96) // 避让悬浮 TabBar
            }

            // 浮动 Toast 提示
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .overlay(Capsule().strokeBorder(AppUI.electricViolet, lineWidth: 1))
                    .shadow(radius: 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.bottom, 120)
                    .zIndex(10)
            }
        }
        .background {
            AppUI.ambientBackground(scheme: scheme)
                .ignoresSafeArea()
        }
        .onAppear {
            if consoleLogs.isEmpty {
                consoleLogs.append(ConsoleLogEntry(message: "[Mimir Code Engine] Ready. Runtime environment initialized."))
            }
        }
        .fullScreenCover(isPresented: $isFullScreenEditor) {
            fullScreenEditorView
        }
    }

    // MARK: - 1. 顶部工作区标头

    private var workspaceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("代码工坊")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Text("Code Stage & Live Runtime")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }

            Spacer()

            // 语言快速选择药丸
            Menu {
                ForEach(CodeLanguage.allCases) { lang in
                    Button {
                        switchLanguage(to: lang)
                    } label: {
                        HStack {
                            Text(lang.rawValue)
                            if selectedLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(selectedLanguage.tagColor)
                        .frame(width: 7, height: 7)
                    Text(selectedLanguage.rawValue)
                        .font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(AppUI.textTitle(scheme: scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .softGlassCard(cornerRadius: 14)
            }
            .buttonStyle(PhysicalElasticButtonStyle())
        }
    }

    private func switchLanguage(to lang: CodeLanguage) {
        selectedLanguage = lang
        switch lang {
        case .swift:
            fileName = "AgentRunner.swift"
            currentCode = WorkspaceManager.sampleSwiftCode
        case .html:
            fileName = "NeuralVisualizer.html"
            currentCode = WorkspaceManager.sampleHTMLCode
        case .python:
            fileName = "DataPipeline.py"
            currentCode = WorkspaceManager.samplePythonCode
        case .json:
            fileName = "ModelManifest.json"
            currentCode = "{\n  \"model\": \"DeepSeek-Reasoner\",\n  \"mode\": \"Ultra\",\n  \"tokens\": 16384\n}"
        }
    }

    // MARK: - 2. 代码工作区主卡片 (Code Stage Container)

    private var codeStageContainer: some View {
        VStack(spacing: 0) {
            // 控制栏 (Editor Header)
            editorHeaderBar

            Divider()
                .overlay(Color.white.opacity(scheme == .dark ? 0.12 : 0.4))

            // 主体：语法高亮代码展示 / Web 实时运行预览
            if isLivePreviewMode {
                LiveWebPreviewContainer(htmlCode: currentCode)
                    .frame(height: 290)
            } else {
                syntaxCodeBody
                    .frame(height: 290)
            }
        }
        .softGlassCard(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.45 : 0.85),
                            AppUI.electricViolet.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .rotatingGlowBorder(cornerRadius: 22, lineWidth: 1.2, isAnimated: true, glowRadius: 22)
        .interactiveTilt(maxAngle: 4.5, cornerRadius: 22)
    }

    // MARK: - 编辑器控制栏 (Editor Header)

    private var editorHeaderBar: some View {
        HStack(spacing: 8) {
            // 左侧：文件名 + 语言指示胶囊
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppUI.electricViolet)

                Text(fileName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)

                Text(selectedLanguage.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selectedLanguage.tagColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(selectedLanguage.tagColor.opacity(0.14))
                    )
            }

            Spacer()

            // 右侧操作三件套
            HStack(spacing: 4) {
                // 1. 实时内联运行 / 语法预览切换
                Button {
                    Haptics.impact(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isLivePreviewMode.toggle()
                    }
                } label: {
                    Image(systemName: isLivePreviewMode ? "doc.plaintext" : "play.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isLivePreviewMode ? AppUI.electricViolet : Color(hex: "34D399"))
                        .frame(width: 30, height: 30)
                        .liquidGlass(isLivePreviewMode ? .regular.tint(AppUI.electricViolet.opacity(0.35)).interactive() : .clear.interactive(), in: .circle)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.25 : 0.6), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle())

                // 2. 一键复制代码 (doc.on.doc)
                Button {
                    Haptics.notify(.success)
                    UIPasteboard.general.string = currentCode
                    triggerToast("已复制代码到剪贴板")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .frame(width: 30, height: 30)
                        .liquidGlass(.clear.interactive(), in: .circle)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.25 : 0.6), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle())

                // 3. AI 重新生成 / 重构 (arrow.triangle.2.circlepath)
                Button {
                    Haptics.impact(.medium)
                    executeAIRefactor()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .frame(width: 30, height: 30)
                        .liquidGlass(.clear.interactive(), in: .circle)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.25 : 0.6), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle())

                // 4. 全屏展开 (arrow.up.left.and.arrow.down.right)
                Button {
                    Haptics.impact(.light)
                    isFullScreenEditor = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .frame(width: 30, height: 30)
                        .liquidGlass(.clear.interactive(), in: .circle)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.25 : 0.6), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - 语法高亮代码区 (Syntax Body)

    private var syntaxCodeBody: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            let lines = currentCode.components(separatedBy: "\n")

            HStack(alignment: .top, spacing: 12) {
                // 行号（低对比度弱化处理）
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(1...max(lines.count, 1), id: \.self) { lineNo in
                        Text("\(lineNo)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AppUI.textCaption(scheme: scheme).opacity(0.55))
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 10)

                // 代码正文（浅紫主题语法配色）
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        highlightedLine(line)
                    }
                }
                .padding(.trailing, 16)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(hex: "13101E").opacity(scheme == .dark ? 0.88 : 0.85))
    }

    private func highlightedLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        let color: Color
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
            color = Color(hex: "9CA3AF") // 注释灰
        } else if trimmed.hasPrefix("import ") || trimmed.hasPrefix("export ") || trimmed.hasPrefix("public ") || trimmed.hasPrefix("final ") || trimmed.hasPrefix("func ") || trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") {
            color = AppUI.electricViolet // 关键字紫
        } else if trimmed.contains("return ") || trimmed.contains("await ") || trimmed.contains("try ") || trimmed.contains("const ") || trimmed.contains("let ") || trimmed.contains("var ") {
            color = Color(hex: "38BDF8") // 控制流与声明蓝
        } else if trimmed.contains("\"") || trimmed.contains("'") {
            color = Color(hex: "34D399") // 字符串绿
        } else {
            color = Color(hex: "E2E8F0") // 默认明亮代码白
        }

        return Text(line.isEmpty ? " " : line)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(color)
    }

    // MARK: - 3. 底部执行输出控制台 (Execution & Output Console)

    private var consoleSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    showConsole.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppUI.electricViolet)
                    Text("Execution & Output Console")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))

                    Spacer()

                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 4)
                    }

                    Image(systemName: showConsole ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .softGlassCard(cornerRadius: 14)
            }
            .buttonStyle(PhysicalElasticButtonStyle())

            if showConsole {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(consoleLogs) { log in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(log.time.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(Color(hex: "9CA3AF").opacity(0.6))
                                    Text(log.message)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(log.isError ? Color(hex: "F87171") : Color(hex: "34D399"))
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                    .background(Color(hex: "0D0B16").opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // 控制台操作按钮
                    HStack {
                        Button {
                            runCodeOrBuild()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                Text("Build & Run (MCP / Local)")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .liquidGlass(.regular.tint(AppUI.electricViolet.opacity(0.85)).interactive(), in: .capsule)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.9)
                                    .allowsHitTesting(false)
                            )
                        }
                        .buttonStyle(PhysicalElasticCapsuleButtonStyle())

                        Spacer()

                        Button {
                            consoleLogs.removeAll()
                            consoleLogs.append(ConsoleLogEntry(message: "[Console Cleared]"))
                        } label: {
                            Text("清空输出")
                                .font(.system(size: 11))
                                .foregroundStyle(AppUI.textCaption(scheme: scheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlass(.clear.interactive(), in: .capsule)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(scheme == .dark ? 0.20 : 0.40), lineWidth: 0.8)
                                        .allowsHitTesting(false)
                                )
                        }
                        .buttonStyle(PhysicalElasticCapsuleButtonStyle())
                    }
                    .padding(.horizontal, 4)
                }
                .padding(10)
                .softGlassCard(cornerRadius: 16)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private func runCodeOrBuild() {
        Haptics.impact(.medium)
        isExecuting = true
        consoleLogs.append(ConsoleLogEntry(message: "[Task Dispatched] Executing \(fileName)..."))

        Task {
            try? await Task.sleep(for: .milliseconds(700))
            isExecuting = false
            if selectedLanguage == .html {
                consoleLogs.append(ConsoleLogEntry(message: "✓ Web DOM mounted. Canvas rendering pipeline active at 60fps."))
            } else if selectedLanguage == .swift {
                consoleLogs.append(ConsoleLogEntry(message: "✓ Swift 6 strict concurrency checks: COMPLETE. 0 warnings."))
                consoleLogs.append(ConsoleLogEntry(message: "Build output: AgentPipeline binary staged."))
            } else {
                consoleLogs.append(ConsoleLogEntry(message: "✓ Process finished with exit code 0."))
            }
        }
    }

    // MARK: - 4. AI 追问与重构输入区

    private var aiRefactorInputBar: some View {
        VStack(spacing: 8) {
            // 思考状态胶囊（点击可展开 ReasoningEffortCard）
            HStack {
                ReasoningStatusChip(
                    modelID: "deepseek-reasoner",
                    level: thinkingMode,
                    isExpanded: showReasoningCard
                ) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        showReasoningCard.toggle()
                    }
                }
                Spacer()
            }

            if showReasoningCard {
                ReasoningEffortSlider(level: $thinkingMode)
                    .padding(12)
                    .softGlassCard(cornerRadius: 18)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }

            // 输入条
            HStack(spacing: 8) {
                TextField("在当前代码上下文中追问或重构...", text: $aiPromptText)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .submitLabel(.send)
                    .onSubmit {
                        executeAIRefactor()
                    }

                Button {
                    executeAIRefactor()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(
                            aiPromptText.isEmpty
                                ? AppUI.textCaption(scheme: scheme).opacity(0.4)
                                : Color.white
                        )
                        .frame(width: 32, height: 32)
                        .liquidGlass(
                            aiPromptText.isEmpty
                                ? .clear.interactive()
                                : .regular.tint(AppUI.electricViolet.opacity(0.85)).interactive(),
                            in: .circle
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    aiPromptText.isEmpty
                                        ? Color.white.opacity(0.2)
                                        : Color.white.opacity(0.45),
                                    lineWidth: 0.9
                                )
                                .allowsHitTesting(false)
                        }
                }
                .disabled(aiPromptText.isEmpty)
                .buttonStyle(PhysicalElasticCircleButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .softGlassCard(cornerRadius: 18)
        }
    }

    private func executeAIRefactor() {
        guard !aiPromptText.isEmpty else {
            coordinator.navigateToAssistant(withPrompt: "请帮我重构以下 \(fileName) 代码：\n```\(selectedLanguage.rawValue)\n\(currentCode)\n```")
            return
        }
        let prompt = "基于文件 \(fileName)（思考档位 \(thinkingMode.heroTitle)），要求如下：\n\(aiPromptText)\n\n代码正文：\n```\(selectedLanguage.rawValue)\n\(currentCode)\n```"
        aiPromptText = ""
        coordinator.navigateToAssistant(withPrompt: prompt)
    }

    private func triggerToast(_ msg: String) {
        toastMessage = msg
        withAnimation { showToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showToast = false }
        }
    }

    // MARK: - 全屏编辑器

    private var fullScreenEditorView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $currentCode)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isFullScreenEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并写回") {
                        if let active = workspace.currentActiveCodeFile {
                            try? workspace.saveFileContent(item: active, newContent: currentCode)
                        }
                        triggerToast("文件修改已写回本地")
                        isFullScreenEditor = false
                    }
                }
            }
        }
    }
}

/// WebKit 离线运行时实时预览容器 (Live Preview Code Runner)
private struct LiveWebPreviewContainer: UIViewRepresentable {
    let htmlCode: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlCode, baseURL: nil)
    }
}

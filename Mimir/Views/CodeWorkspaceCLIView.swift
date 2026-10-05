import SwiftUI

/// Tab 4: 代码工坊与 CLI 控制台（CodeWorkspaceCLIView）。
///
/// 采用上下分屏沉浸式架构：
/// - **上半部**：VS Code CLI 终端视窗（深暗色流体玻璃、红黄绿三色控制点、运行按钮、SF Mono 等宽流式编译输出）；
/// - **下半部**：与终端联动的实时对话气泡流与支持 `/run` 快捷指令的输入栏（动态避让底部四大金刚 TabBar）。
struct CodeWorkspaceCLIView: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(AppSettings.self) private var settings

    @State private var terminalLogs: [CLILogLine] = []
    @State private var chatMessages: [CLIChatMessage] = []
    @State private var inputText: String = ""
    @State private var isExecuting: Bool = false
    @State private var isKeyboardVisible: Bool = false
    @FocusState private var isInputFocused: Bool

    struct CLILogLine: Identifiable, Sendable {
        let id = UUID()
        let text: String
        let level: LogLevel
        let timestamp: Date = Date()

        enum LogLevel: Sendable {
            case command
            case info
            case success
            case warning
            case error
        }
    }

    struct CLIChatMessage: Identifiable, Sendable {
        let id = UUID()
        let isUser: Bool
        let text: String
        let timestamp: Date = Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工作区标头
            cliHeaderBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            // 上半部：VS Code CLI 终端视窗
            terminalWindowSection
                .frame(maxHeight: 260)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // 下半部：与终端联动的对话流与快捷控制台
            conversationAndInputSection
        }
        .background {
            AppUI.ambientBackground(scheme: scheme)
                .ignoresSafeArea()
        }
        .onAppear {
            if terminalLogs.isEmpty {
                bootstrapCLI()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isKeyboardVisible = false
            }
        }
    }

    // MARK: - 1. 顶部工作区标头

    private var cliHeaderBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("代码工坊")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))

                    Text("CLI")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                }

                Text("VS Code Terminal & Runtime Assistant")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }

            Spacer()

            // 状态小胶囊
            HStack(spacing: 5) {
                Circle()
                    .fill(isExecuting ? Color.orange : Color(hex: "34D399"))
                    .frame(width: 7, height: 7)
                    .shadow(color: (isExecuting ? Color.orange : Color(hex: "34D399")).opacity(0.6), radius: 3)

                Text(isExecuting ? "BUILDING" : "IDLE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .liquidGlass(.regular, in: .capsule)
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 0.8)
            )
        }
    }

    // MARK: - 2. 上半部：VS Code CLI 终端视窗

    private var terminalWindowSection: some View {
        VStack(spacing: 0) {
            // 终端标题栏：红黄绿三色控制点 + 终端名称 + 运行/清空按钮
            HStack(spacing: 8) {
                // macOS / VS Code 三色控制点
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(Color(red: 0.15, green: 0.79, blue: 0.25))
                        .frame(width: 10, height: 10)
                }
                .padding(.leading, 4)

                Spacer()

                // 终端窗口标题
                HStack(spacing: 4) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(accent)

                    Text("mimir-cli ~ zsh (80x24)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                }

                Spacer()

                // 清空终端按钮
                Button {
                    Haptics.impact(.light)
                    withAnimation {
                        terminalLogs.removeAll()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle(scale: 0.90))

                // 运行 / 执行按钮
                Button {
                    executeRunCommand()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExecuting ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isExecuting ? "中断" : "运行")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(isExecuting ? Color.red.opacity(0.85) : accent)
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.40), lineWidth: 0.8)
                    )
                    .shadow(color: (isExecuting ? Color.red : accent).opacity(0.50), radius: 6, y: 1)
                }
                .buttonStyle(PhysicalElasticCapsuleButtonStyle())
                .disabled(isExecuting)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.black.opacity(0.55))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 0.6)
            }

            // 终端屏幕输出区
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(terminalLogs) { log in
                            logLineView(log)
                        }

                        // 光标闪烁指示行
                        HStack(spacing: 4) {
                            Text("mimir@local %")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)

                            Rectangle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 7, height: 13)
                                .opacity(isExecuting ? 0.3 : 1.0)
                        }
                        .id("terminal.bottom")
                    }
                    .padding(10)
                }
                .background(Color(red: 0.05, green: 0.04, blue: 0.09).opacity(0.96))
                .onChange(of: terminalLogs.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("terminal.bottom", anchor: .bottom)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            accent.opacity(0.45),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
    }

    private func logLineView(_ log: CLILogLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            switch log.level {
            case .command:
                Text("$")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(log.text)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
            case .info:
                Text(log.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: "9CA3AF"))
            case .success:
                Text(log.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "34D399"))
            case .warning:
                Text(log.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "FBBF24"))
            case .error:
                Text(log.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "F87171"))
            }
        }
    }

    // MARK: - 3. 下半部：终端联动的对话流与快捷控制输入栏

    private var conversationAndInputSection: some View {
        VStack(spacing: 8) {
            // 对话气泡滚动区
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(chatMessages.enumerated()), id: \.element.id) { index, msg in
                            cliMessageBubble(msg)
                                .staggerCascade(index: index)
                        }
                        Color.clear.frame(height: 10).id("chat.bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                .correctedSoftFadeMask(topFade: 12, bottomFade: 24)
                .onChange(of: chatMessages.count) { _, _ in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                        proxy.scrollTo("chat.bottom", anchor: .bottom)
                    }
                }
            }

            // 快捷指令胶囊栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    commandChip(title: "/run", desc: "编译运行") {
                        executeRunCommand()
                    }
                    commandChip(title: "/test", desc: "单测套件") {
                        sendCustomCommand("/test")
                    }
                    commandChip(title: "/analyze", desc: "严格并发静态分析") {
                        sendCustomCommand("/analyze")
                    }
                    commandChip(title: "/clean", desc: "清理缓存") {
                        sendCustomCommand("/clean")
                    }
                }
                .padding(.horizontal, 16)
            }

            // 底部输入框（避让底部四大金刚 TabBar）
            cliInputBar
                .padding(.horizontal, 16)
                .padding(.bottom, isKeyboardVisible ? 8 : 78)
        }
    }

    private func cliMessageBubble(_ msg: CLIChatMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 40) }

            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if !msg.isUser {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                        Text("Mimir Code Agent")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    } else {
                        Text("You")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    }
                }

                Text(msg.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(msg.isUser ? Color.white : AppUI.textTitle(scheme: scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        if msg.isUser {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(accent)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.clear)
                                .liquidGlass(.regular.interactive(), in: .rect(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(accent.opacity(0.35), lineWidth: 0.9)
                                )
                        }
                    }
                    .shadow(
                        color: msg.isUser ? accent.opacity(0.35) : Color.black.opacity(scheme == .dark ? 0.30 : 0.06),
                        radius: 6,
                        y: 2
                    )
            }

            if !msg.isUser { Spacer(minLength: 40) }
        }
    }

    private func commandChip(title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(desc)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlass(.regular.interactive(), in: .capsule)
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(PhysicalElasticCapsuleButtonStyle())
    }

    private var cliInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .padding(.leading, 4)

            TextField("输入 /run 或向代码助手提问…", text: $inputText)
                .font(.system(size: 13.5))
                .foregroundStyle(AppUI.textTitle(scheme: scheme))
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    submitMessage()
                }

            if !inputText.isEmpty {
                Button {
                    submitMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle(scale: 0.90))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .liquidGlass(.regular.interactive(), in: .capsule)
        .overlay(
            Capsule().strokeBorder(accent.opacity(0.40), lineWidth: 1.0)
        )
        .shadow(color: accent.opacity(0.18), radius: 8, y: 2)
    }

    // MARK: - 行为与指令模拟

    private func bootstrapCLI() {
        terminalLogs = [
            CLILogLine(text: "Mimir Interactive CLI Runtime [Version 2.0.26]", level: .info),
            CLILogLine(text: "Loaded Swift 6 Complete Concurrency Mode.", level: .info),
            CLILogLine(text: "Workspace root: /Users/admin/MimirWorkspace", level: .info)
        ]

        chatMessages = [
            CLIChatMessage(
                isUser: false,
                text: "欢迎来到代码工坊。上方是实时 CLI 终端视窗，下方我将为你提供编译诊断与代码重构建议。输入 `/run` 可立即触发构建。"
            )
        ]
    }

    private func executeRunCommand() {
        guard !isExecuting else { return }
        Haptics.impact(.medium)
        isExecuting = true

        terminalLogs.append(CLILogLine(text: "swift build --configuration release -Xswiftc -strict-concurrency=complete", level: .command))

        Task {
            try? await Task.sleep(for: .milliseconds(400))
            terminalLogs.append(CLILogLine(text: "Fetching dependencies (modelcontextprotocol/swift-sdk)...", level: .info))
            try? await Task.sleep(for: .milliseconds(500))
            terminalLogs.append(CLILogLine(text: "Compiling Mimir targets with Swift 6...", level: .info))
            try? await Task.sleep(for: .milliseconds(600))
            terminalLogs.append(CLILogLine(text: "[Build] 0 errors, 0 warnings. Complete concurrency checks passed.", level: .success))
            terminalLogs.append(CLILogLine(text: "✓ Linking Mimir-unsigned.ipa... done (0.68s)", level: .success))

            isExecuting = false

            chatMessages.append(
                CLIChatMessage(
                    isUser: false,
                    text: "终端编译执行成功！Swift 6 严格并发检查通过，未发现任何竞态条件或数据隔离冲突。"
                )
            )
        }
    }

    private func sendCustomCommand(_ cmd: String) {
        Haptics.impact(.light)
        inputText = cmd
        submitMessage()
    }

    private func submitMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.impact(.light)
        inputText = ""

        chatMessages.append(CLIChatMessage(isUser: true, text: trimmed))

        if trimmed == "/run" {
            executeRunCommand()
        } else if trimmed == "/clean" {
            terminalLogs.append(CLILogLine(text: "rm -rf .build && swift package clean", level: .command))
            terminalLogs.append(CLILogLine(text: "Clean complete. Cache cleared.", level: .success))
            chatMessages.append(CLIChatMessage(isUser: false, text: "已清理工程构建缓存与派生数据。"))
        } else if trimmed == "/analyze" {
            terminalLogs.append(CLILogLine(text: "swift-format lint --strict -r Mimir", level: .command))
            terminalLogs.append(CLILogLine(text: "Concurrency isolation: 100% compliant.", level: .success))
            chatMessages.append(CLIChatMessage(isUser: false, text: "静态分析完成：所有异步代码与 Sendable 协议严格符合规范。"))
        } else {
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                chatMessages.append(
                    CLIChatMessage(
                        isUser: false,
                        text: "收到关于「\(trimmed)」的调试请求。已同步检查当前代码逻辑与 AST 语法树，你可以点击上方「运行」查看实机输出。"
                    )
                )
            }
        }
    }
}

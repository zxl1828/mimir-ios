import SwiftUI
import UIKit

/// 单条消息卡片（Codex 桌面端 Agent Turn 风格，自动适配浅色与深色模式）。
struct MessageBubble: View {

    let message: ChatMessage
    var showsThinkingByDefault: Bool = false
    var isHighlighted: Bool = false
    var onCopy: () -> Void = {}
    var onRegenerate: () -> Void = {}
    var onRegenerateHere: () -> Void = {}
    var onSwitchVersion: (Int) -> Void = { _ in }
    var onQuote: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenMemory: (UUID) -> Void = { _ in }
    var onTapImage: (UIImage) -> Void = { _ in }

    @State private var thinkingExpanded = false
    @State private var showsUsage = false
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(AppSettings.self) private var settings
    /// 单条消息的朗读引擎（懒加载，只在这条气泡里用）。
    @State private var speaker: SystemSpeechEngine?
    @State private var isSpeaking = false
    /// 工具调用遥测（内存态，用于卡片底部的审计胶囊）
    @State private var telemetry = ToolCallTelemetry.shared
    @State private var showTelemetrySheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }
            content
            if message.role != .user { Spacer(minLength: 18) }
        }
        .padding(.horizontal, 14)
        .onAppear {
            if showsThinkingByDefault && !thinkingExpanded {
                thinkingExpanded = true
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .sheet(isPresented: $showTelemetrySheet) {
            ToolCallInspectorSheet(messageID: message.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    // MARK: - 用户消息（Glassmorphic Bubble with Purple Glow Edge）

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            nameLabel("User Input · 我", isUser: true)

            if !message.quotedPreview.isEmpty {
                quotedChip
            }

            if let data = message.attachmentData, let image = UIImage(data: data) {
                Button {
                    onTapImage(image)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                        )
                }
                .buttonStyle(PhysicalElasticButtonStyle(cornerRadius: 16))
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(AppUI.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .liquidGlass(.regular.tint(accent.opacity(scheme == .dark ? 0.65 : 0.90)).interactive(), in: .rect(cornerRadius: AppUI.bubbleRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppUI.bubbleRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.65),
                                        accent.opacity(0.90),
                                        AppUI.neonViolet.opacity(0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.15
                            )
                    )
                    .shadow(color: accent.opacity(scheme == .dark ? 0.45 : 0.28), radius: 12, y: 4)
            }

            metaRow(isUser: true)
        }
        .contextMenu { menuItems }
    }

    // MARK: - 助手消息（Agent Turn Card）

    private func nameLabel(_ text: String, isUser: Bool) -> some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 0) }
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppUI.label3)
                .padding(.horizontal, 2)
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部角色标识 + TTS 朗读悬浮圆钮
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: accent.opacity(0.8), radius: 4)

                Text(message.agentName.isEmpty ? "Assistant" : message.agentName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppUI.label2)

                if !message.skillName.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("/" + message.skillName)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppUI.label2)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(AppUI.fill))
                }

                Spacer(minLength: 0)
                speakButton
            }

            if message.hasVisibleThinking {
                thinkingSection
            }

            if message.isError && !message.errorText.isEmpty {
                errorSection
            } else if message.text.isEmpty && message.isStreaming {
                HStack(spacing: 10) {
                    MimirMascot(size: 30, mood: .thinking)
                    Text("正在推演生成…")
                        .font(AppUI.footnote)
                        .foregroundStyle(AppUI.label2)
                }
                .padding(.vertical, 4)
            } else {
                MarkdownText(raw: message.renderedText, isStreaming: message.isStreaming)
            }

            if !message.memoryHitIDs.isEmpty {
                memoryChips
            }

            if message.versionCount > 1 {
                versionSwitcher
            }

            telemetryCapsule(for: message.id)

            metaRow(isUser: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Agent Turn 卡片：液态玻璃底衬
        .liquidGlass(cornerRadius: AppUI.bubbleRadius, glowIntensity: 0.18)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: AppUI.bubbleRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.85), lineWidth: 1.6)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu { menuItems }
    }

    /// 悬浮微光液态朗读按钮：用系统原生 `AVSpeechSynthesizer` 念这条回复。
    // MARK: - 工具调用遥测胶囊

    /// 卡片底部的遥测胶囊：`工具调用 · N 次 | 本机数据访问 · M 次`，点击打开审计面板。
    /// 只有真的有记录时才出现，不给普通回复增加噪音。
    @ViewBuilder
    private func telemetryCapsule(for messageID: UUID) -> some View {
        let counts = telemetry.counts(for: messageID)
        if counts.tools > 0 || counts.accesses > 0 {
            Button {
                Haptics.impact(.light)
                showTelemetrySheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("工具调用 · " + String(counts.tools) + "次")
                    Text("|")
                        .foregroundStyle(AppUI.label3)
                    Text("本机数据访问 · " + String(counts.accesses) + "次")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppUI.label3)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlass(cornerRadius: 13, glowIntensity: 0.35)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看工具调用与数据访问详情")
        }
    }

    private var speakButton: some View {
        Button {
            toggleSpeech()
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .liquidGlass(cornerRadius: 14, isHighlighted: isSpeaking, glowIntensity: 0.5)
                .contentShape(Circle())
        }
        .buttonStyle(PhysicalElasticCircleButtonStyle())
        .accessibilityLabel(isSpeaking ? "停止朗读" : "朗读这条回复")
    }

    @MainActor
    private func toggleSpeech() {
        let engine: SystemSpeechEngine
        if let speaker {
            engine = speaker
        } else {
            let created = SystemSpeechEngine()
            speaker = created
            engine = created
        }
        engine.preferredVoiceIdentifier = settings.voice.systemVoiceIdentifier

        if isSpeaking {
            engine.stop()
            isSpeaking = false
            return
        }

        engine.speak(message.text, rate: settings.voice.speechRate)
        isSpeaking = true
        // 说完自动复位；用轮询而不是代理回调，避免跨隔离域捕获。
        Task {
            while engine.isSpeaking {
                try? await Task.sleep(for: .milliseconds(250))
            }
            isSpeaking = false
        }
    }

    /// 思考折叠卡片（Thinking Stream / Thought Disclosure）：紫脉冲脑电图标 + 档位徽标 + 磨砂紫底衬。
    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selectionChanged()
                withAnimation(AppAnimation.chip) { thinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.6), radius: 4)

                    Text(message.isStreaming && !thinkingExpanded ? "Thinking Stream · 正在思考…" : "Thinking Stream")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppUI.label)

                    Text("(\(message.thinkingMode.title))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent.opacity(scheme == .dark ? 0.20 : 0.12))
                        )

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppUI.label2)
                        .rotationEffect(.degrees(thinkingExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if thinkingExpanded {
                Text(message.thinkingText)
                    .font(AppUI.footnote)
                    .foregroundStyle(AppUI.label2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(accent.opacity(0.55))
                            .frame(width: 2.5)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    scheme == .dark
                        ? Color(red: 0.14, green: 0.09, blue: 0.25).opacity(0.72)
                        : accent.opacity(0.08)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(accent.opacity(scheme == .dark ? 0.34 : 0.24), lineWidth: 1)
        )
    }

    private var errorSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.orange)
            Text(message.errorText)
                .font(AppUI.footnote)
                .foregroundStyle(AppUI.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var quotedChip: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accent)
                .frame(width: 2.5, height: 14)
            Text(message.quotedPreview)
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(AppUI.fill)
        )
    }

    private var memoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.memoryHitIDs, id: \.self) { id in
                    Button {
                        onOpenMemory(id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("记忆")
                                .font(AppUI.caption)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 多版本切换器：同一位置保留多次生成的回答，横向切换对比。
    private var versionSwitcher: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.selectionChanged()
                onSwitchVersion(message.activeVersionIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(message.activeVersionIndex <= 0)
            .opacity(message.activeVersionIndex <= 0 ? 0.35 : 1)

            Text(message.versionLabel)
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label2)
                .monospacedDigit()

            Button {
                Haptics.selectionChanged()
                onSwitchVersion(message.activeVersionIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(message.activeVersionIndex >= message.versionCount - 1)
            .opacity(message.activeVersionIndex >= message.versionCount - 1 ? 0.35 : 1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(AppUI.label2)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(AppUI.fill)
        )
        .frame(maxWidth: 120, alignment: .leading)
    }

    private func metaRow(isUser: Bool) -> some View {
        HStack(spacing: 8) {
            if message.isInterrupted {
                Text("已打断")
                    .font(AppUI.caption)
                    .foregroundStyle(Color.orange)
            }

            if message.usage.total > 0 {
                Button {
                    showsUsage.toggle()
                } label: {
                    Text(showsUsage
                         ? "输入 \(message.usage.promptTokens) · 输出 \(message.usage.completionTokens + message.usage.reasoningTokens)"
                         : "\(message.usage.total) tokens")
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label3)
                }
                .buttonStyle(.plain)
            }

            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
        }
        .animation(.easeInOut(duration: 0.18), value: showsUsage)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            UIPasteboard.general.string = message.copyableText
            Haptics.impact(.light)
            onCopy()
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            onQuote()
        } label: {
            Label("引用", systemImage: "quote.opening")
        }

        if message.role == .user {
            Button {
                onEdit()
            } label: {
                Label("编辑并重发", systemImage: "pencil")
            }
        } else {
            Button {
                onRegenerate()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }

            Button {
                onRegenerateHere()
            } label: {
                Label("从这里重新生成", systemImage: "arrow.triangle.branch")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}

// MARK: - 工具调用审计面板

/// 点击遥测胶囊后的审计面板：列出这次回答执行过的工具与本机数据访问。
private struct ToolCallInspectorSheet: View {

    let messageID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    @State private var telemetry = ToolCallTelemetry.shared

    private var invocations: [ToolCallTelemetry.ToolInvocation] {
        telemetry.invocations(for: messageID)
    }

    private var accesses: [ToolCallTelemetry.LocalDataAccess] {
        telemetry.accesses(for: messageID)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if invocations.isEmpty {
                        Text("这次回答没有调用工具。")
                            .font(AppUI.footnote)
                            .foregroundStyle(AppUI.label2)
                    }
                    ForEach(invocations) { item in
                        toolRow(item)
                    }
                } header: {
                    Text("执行的工具")
                }

                Section {
                    if accesses.isEmpty {
                        Text("这次回答没有读取本机数据。")
                            .font(AppUI.footnote)
                            .foregroundStyle(AppUI.label2)
                    }
                    ForEach(accesses) { item in
                        accessRow(item)
                    }
                } header: {
                    Text("本机数据访问")
                } footer: {
                    Text("记录只保留在本机内存中，退出 App 即清空，不会上传。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具调用审计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func toolRow(_ item: ToolCallTelemetry.ToolInvocation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.succeeded == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(item.succeeded == false ? Color.red : Color.green)
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(item.statusText)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                if let duration = item.duration {
                    Text(String(format: "%.2fs", duration))
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label3)
                        .monospacedDigit()
                }
            }
            Text(item.startedAt, format: .dateTime.hour().minute().second())
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
            if !item.argumentsSummary.isEmpty {
                Text("参数：" + item.argumentsSummary)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
                    .lineLimit(3)
            }
            if !item.resultSummary.isEmpty {
                Text("结果：" + item.resultSummary)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private func accessRow(_ item: ToolCallTelemetry.LocalDataAccess) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.framework)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.detail)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
                Text(item.occurredAt, format: .dateTime.hour().minute().second())
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
            }
        }
        .padding(.vertical, 2)
    }
}

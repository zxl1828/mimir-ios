import SwiftUI
import UIKit

/// 单条消息气泡。用户消息右对齐蓝底白字，助手消息左对齐浅灰卡片。
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

    @State private var thinkingExpanded = false
    @State private var showsUsage = false
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(AppSettings.self) private var settings
    /// 单条消息的朗读引擎（懒加载，只在这条气泡里用）。
    @State private var speaker: SystemSpeechEngine?
    @State private var isSpeaking = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 44) }
            content
            if message.role != .user { Spacer(minLength: 24) }
        }
        .padding(.horizontal, 14)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    @ViewBuilder
    private var content: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    // MARK: - 用户消息

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            nameLabel("我", isUser: true)

            if !message.quotedPreview.isEmpty {
                quotedChip
            }

            if let data = message.attachmentData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(AppUI.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: AppUI.bubbleRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.98), accent.opacity(0.74)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppUI.bubbleRadius, style: .continuous)
                            .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(0.38), radius: 12, y: 4)
            }

            metaRow(isUser: true)
        }
        .contextMenu { menuItems }
    }

    // MARK: - 助手消息

    /// 微信式名称标识：一眼分清「我」和「模型」。
    private func nameLabel(_ text: String, isUser: Bool) -> some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 0) }
            Text(text)
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
                .padding(.horizontal, 2)
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("模型")
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                Spacer(minLength: 0)
                speakButton
            }

            if message.hasVisibleThinking {
                thinkingSection
            }

            if message.isError && !message.errorText.isEmpty {
                errorSection
            } else if message.text.isEmpty && message.isStreaming {
                HStack(spacing: 8) {
                    MimirMascot(size: 26, mood: .thinking)
                    Text("正在生成…")
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

            metaRow(isUser: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Agent Turn 卡片：液态玻璃底衬
        .liquidGlass(cornerRadius: AppUI.bubbleRadius, glowIntensity: 0.16)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: AppUI.bubbleRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.8), lineWidth: 1.6)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu { menuItems }
    }

    /// 悬浮微光液态朗读按钮：用系统合成念这条回复。
    private var speakButton: some View {
        Button {
            toggleSpeech()
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .liquidGlass(cornerRadius: 13, isHighlighted: isSpeaking, glowIntensity: 0.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.selectionChanged()
                withAnimation(AppAnimation.chip) { thinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(message.isStreaming && thinkingExpanded == false ? "正在思考…" : "思考过程")
                        .font(AppUI.chip)
                    if message.thinkingMode != nil {
                        Text(message.thinkingMode?.title ?? "")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(accent.opacity(0.16)))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(thinkingExpanded ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppUI.label2)
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
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accent.opacity(0.35))
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(scheme == .dark ? Color.black.opacity(0.38) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var errorSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.warning)
            Text(message.errorText)
                .font(AppUI.footnote)
                .foregroundStyle(AppUI.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.warning.opacity(0.10))
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
                        .foregroundStyle(AppUI.label2)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(AppUI.fill))
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
            if !message.agentName.isEmpty {
                Text(message.agentName)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
            }
            if !message.skillName.isEmpty {
                Text("/" + message.skillName)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
            }
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

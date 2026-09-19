import SwiftUI
import UIKit

/// 单条消息气泡。用户消息右对齐实色渐变，助手消息左对齐玻璃卡片。
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
                    .font(AppFont.bubbleBody)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.bubbleCorner, style: .continuous)
                            .fill(AppColor.accentGradient)
                    )
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
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isUser ? AppColor.secondaryText : AppColor.brandIndigo)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill((isUser ? AppColor.secondaryText : AppColor.brandIndigo).opacity(0.12))
                )
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            nameLabel("模型", isUser: false)

            if message.hasVisibleThinking {
                thinkingSection
            }

            if message.isError && !message.errorText.isEmpty {
                errorSection
            } else if message.text.isEmpty && message.isStreaming {
                HStack(spacing: 8) {
                    MimirMascot(size: 26, mood: .thinking)
                    Text("正在生成…")
                        .font(AppFont.hint)
                        .foregroundStyle(AppColor.secondaryText)
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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 22)
        .glassHairline(cornerRadius: 22)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppColor.brandIndigo.opacity(0.85), lineWidth: 1.6)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu { menuItems }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.selectionChanged()
                withAnimation(AppAnimation.chip) { thinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message.isStreaming && thinkingExpanded == false ? "正在思考…" : "思考过程")
                        .font(AppFont.chipCompact)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(thinkingExpanded ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppColor.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if thinkingExpanded {
                Text(message.thinkingText)
                    .font(AppFont.codeSmall)
                    .foregroundStyle(AppColor.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(AppColor.brandPurple.opacity(0.4))
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var errorSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.warning)
            Text(message.errorText)
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
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
                .fill(Color.white.opacity(0.7))
                .frame(width: 2.5, height: 14)
            Text(message.quotedPreview)
                .font(AppFont.chipCompact)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(Color.white.opacity(0.16))
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
                                .font(AppFont.chipCompact)
                        }
                        .foregroundStyle(AppColor.brandPurple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(AppColor.brandPurple.opacity(0.12)))
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
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.secondaryText)
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
        .foregroundStyle(AppColor.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(AppColor.secondaryText.opacity(0.09))
        )
        .frame(maxWidth: 120, alignment: .leading)
    }

    private func metaRow(isUser: Bool) -> some View {
        HStack(spacing: 8) {
            if !message.agentName.isEmpty {
                Text(message.agentName)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(isUser ? Color.white.opacity(0.75) : AppColor.brandIndigo)
            }
            if !message.skillName.isEmpty {
                Text("/" + message.skillName)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(isUser ? Color.white.opacity(0.75) : AppColor.brandPurple)
            }
            if message.isInterrupted {
                Text("已打断")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(isUser ? Color.white.opacity(0.7) : AppColor.warning)
            }

            if message.usage.total > 0 {
                Button {
                    showsUsage.toggle()
                } label: {
                    Text(showsUsage
                         ? "输入 \(message.usage.promptTokens) · 输出 \(message.usage.completionTokens + message.usage.reasoningTokens)"
                         : "\(message.usage.total) tokens")
                        .font(AppFont.chipCompact)
                        .foregroundStyle(isUser ? Color.white.opacity(0.6) : AppColor.tertiaryText)
                }
                .buttonStyle(.plain)
            }

            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(AppFont.chipCompact)
                .foregroundStyle(isUser ? Color.white.opacity(0.55) : AppColor.tertiaryText)
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

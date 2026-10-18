import SwiftUI

/// 实时转写与推理上下文悬浮卡片（LiveTranscriptSlab）。
///
/// 展示真实的用户转写与 Mimir 回复；固定布局高度，避免流式文本更新时挤动底部控制岛。
public struct LiveTranscriptSlab: View {

    public enum DisplayMode: Sendable {
        case liveDuplex
        case transcriptionCards
    }

    public var displayMode: DisplayMode = .liveDuplex
    public var userQuery: String?
    public var aiResponse: String?
    public var statusHint: String = "等待语音输入"
    public var isCompact: Bool = false
    public var onMinutesTapped: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    // 核心色彩令牌
    private let irisViolet = Color(hex: "7D52F4")
    private let electricViolet = Color(hex: "9B70FF")
    private let darkCard = Color(hex: "21182F")
    private let darkText = Color(hex: "F2ECFA")

    public init(
        displayMode: DisplayMode = .liveDuplex,
        userQuery: String? = nil,
        aiResponse: String? = nil,
        statusHint: String = "等待语音输入",
        isCompact: Bool = false,
        onMinutesTapped: (() -> Void)? = nil
    ) {
        self.displayMode = displayMode
        self.userQuery = userQuery
        self.aiResponse = aiResponse
        self.statusHint = statusHint
        self.isCompact = isCompact
        self.onMinutesTapped = onMinutesTapped
    }

    public var body: some View {
        VStack(spacing: isCompact ? 6 : 8) {
            if displayMode == .liveDuplex {
                liveDuplexSlab
            } else {
                transcriptionCardsSlab
            }

            // 底部居中悬浮状态标签
            bottomStatusBadge
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 160 : 194, alignment: .top)
        .transaction { $0.animation = nil }
    }

    // MARK: - 1. 深色全双工形态卡片 (参考图 1)

    private var liveDuplexSlab: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            // 用户提问通道（顶部淡紫字，末尾带微型麦克风图标）
            HStack(alignment: .top, spacing: 8) {
                Text(effectiveUserText)
                    .font(.system(size: isCompact ? 14 : 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(scheme == .dark ? Color(hex: "C8B6FF") : irisViolet)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 30 : 38, maxHeight: isCompact ? 30 : 38, alignment: .topLeading)

                Spacer(minLength: 4)

                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? Color(hex: "C8B6FF") : irisViolet)
                    .padding(.top, 2)
            }

            // AI 实时推理与响应通道（纯白/浅紫高亮，带发光闪烁光标）
            HStack(alignment: .bottom, spacing: 2) {
                Text(effectiveAIText)
                    .font(.system(size: isCompact ? 14.5 : 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(scheme == .dark ? darkText : Color(hex: "2F2440"))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 38 : 58, maxHeight: isCompact ? 38 : 58, alignment: .topLeading)

                // 发光紫色呼吸闪烁光标
                if !aiResponseIsEmpty {
                    Rectangle()
                        .fill(electricViolet)
                        .frame(width: 2.2, height: 18)
                        .opacity(0.8)
                        .shadow(color: electricViolet.opacity(0.35), radius: 3)
                        .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isCompact ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 高折射毛玻璃底板 + 0.8pt 鸢尾紫微光描边
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(scheme == .dark ? darkCard.opacity(0.94) : Color.white.opacity(0.84))
        }
        .liquidGlass(.regular, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(scheme == .dark ? 0.34 : 0.45), location: 0.0),
                            .init(color: irisViolet.opacity(scheme == .dark ? 0.52 : 0.40), location: 0.45),
                            .init(color: electricViolet.opacity(scheme == .dark ? 0.44 : 0.35), location: 0.80),
                            .init(color: Color.white.opacity(scheme == .dark ? 0.12 : 0.20), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
        .shadow(color: irisViolet.opacity(scheme == .dark ? 0.34 : 0.25), radius: 24, x: 0, y: 10)
    }

    // MARK: - 2. 浅色转写形态多卡片 (参考图 2)

    private var transcriptionCardsSlab: some View {
        VStack(spacing: isCompact ? 6 : 8) {
            transcriptCard(title: "你", text: effectiveUserText, tint: irisViolet)
            transcriptCard(title: "Mimir", text: effectiveAIText, tint: Color(hex: "35264A"))
        }
    }

    private func transcriptCard(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: isCompact ? 8 : 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle((scheme == .dark ? Color(hex: "D6C9F0") : tint).opacity(0.78))
            Text(text)
                .font(.system(size: isCompact ? 12.5 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(scheme == .dark ? darkText : tint)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: isCompact ? 26 : 36, maxHeight: isCompact ? 26 : 36, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            scheme == .dark ? darkCard.opacity(0.94) : Color.white.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .liquidGlass(.regular, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.78), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 3. 底部悬浮状态提示标签

    private var bottomStatusBadge: some View {
        HStack(spacing: 8) {
            Text(statusHint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(scheme == .dark ? Color(hex: "C5B8D8") : Color(hex: "645A70"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onMinutesTapped {
                Button {
                    Haptics.impact(.light)
                    onMinutesTapped()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "text.badge.checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("会议纪要")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(electricViolet)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background {
            Capsule(style: .continuous)
                .fill(scheme == .dark ? darkCard.opacity(0.96) : Color.white.opacity(0.72))
        }
        .overlay {
            Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.22 : 0.80), lineWidth: 0.7)
        }
    }

    // MARK: - 文本缺省与真实回退计算

    private var effectiveUserText: String {
        if let userQuery, !userQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userQuery
        }
        return "等待语音输入…"
    }

    private var effectiveAIText: String {
        if let aiResponse, !aiResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return aiResponse
        }
        return "Mimir 的回复会显示在这里。"
    }

    private var aiResponseIsEmpty: Bool {
        aiResponse?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

import SwiftUI

/// 实时转写与推理上下文悬浮卡片（LiveTranscriptSlab）。
///
/// 严格复刻参考图 1 与参考图 2 的双通道排版与高透光毛玻璃质感：
/// - **深色全双工形态（参考图 1）**：高折射高透光毛玻璃底板，边缘覆盖 0.8pt 鸢尾紫微光描边；
///   上层为用户语音输入（淡紫字体 + 麦克风图标），下层为 AI 实时流式推理（纯白/浅紫粗体 + 发光紫色闪烁光标）；
///   底部悬浮小字状态标签 (`Listening actively · Tap mic or speak freely`)。
/// - **浅色转写形态（参考图 2）**：双层时间戳沉浸卡片 (`[00:01:24]` / `[00:03:55]`)，包含 `Translate` 与 `Live Summary` 胶囊。
public struct LiveTranscriptSlab: View {

    public enum DisplayMode: Sendable {
        case liveDuplex
        case transcriptionCards
    }

    public var displayMode: DisplayMode = .liveDuplex
    public var userQuery: String?
    public var aiResponse: String?
    public var statusHint: String = "Listening actively · Tap mic or speak freely"
    public var onMinutesTapped: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    // 光标闪烁呼吸态
    @State private var cursorVisible: Bool = true

    // 核心色彩令牌
    private let irisViolet = Color(hex: "7D52F4")
    private let electricViolet = Color(hex: "9B70FF")
    private let lavenderText = Color(hex: "BCA8DC")
    private let deepPlumCard = Color(hex: "1F1235")

    public init(
        displayMode: DisplayMode = .liveDuplex,
        userQuery: String? = nil,
        aiResponse: String? = nil,
        statusHint: String = "Listening actively · Tap mic or speak freely",
        onMinutesTapped: (() -> Void)? = nil
    ) {
        self.displayMode = displayMode
        self.userQuery = userQuery
        self.aiResponse = aiResponse
        self.statusHint = statusHint
        self.onMinutesTapped = onMinutesTapped
    }

    public var body: some View {
        VStack(spacing: 8) {
            if displayMode == .liveDuplex {
                liveDuplexSlab
            } else {
                transcriptionCardsSlab
            }

            // 底部居中悬浮状态标签
            bottomStatusBadge
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }

    // MARK: - 1. 深色全双工形态卡片 (参考图 1)

    private var liveDuplexSlab: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 用户提问通道（顶部淡紫字，末尾带微型麦克风图标）
            HStack(alignment: .top, spacing: 8) {
                Text(effectiveUserText)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(lavenderText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(electricViolet)
                    .padding(.top, 2)
            }

            // AI 实时推理与响应通道（纯白/浅紫高亮，带发光闪烁光标）
            HStack(alignment: .bottom, spacing: 2) {
                Text(effectiveAIText)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // 发光紫色呼吸闪烁光标
                Rectangle()
                    .fill(electricViolet)
                    .frame(width: 2.2, height: 18)
                    .opacity(cursorVisible ? 1.0 : 0.15)
                    .shadow(color: electricViolet.opacity(0.8), radius: 4)
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 高折射毛玻璃底板 + 0.8pt 鸢尾紫微光描边
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    scheme == .dark
                        ? deepPlumCard.opacity(0.68)
                        : Color.white.opacity(0.82)
                )
        }
        .liquidGlass(.regular, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.45), location: 0.0),
                            .init(color: irisViolet.opacity(0.40), location: 0.45),
                            .init(color: electricViolet.opacity(0.35), location: 0.80),
                            .init(color: Color.white.opacity(0.20), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
        .shadow(color: irisViolet.opacity(0.25), radius: 24, x: 0, y: 10)
    }

    // MARK: - 2. 浅色转写形态多卡片 (参考图 2)

    private var transcriptionCardsSlab: some View {
        VStack(spacing: 8) {
            // 上层历史转写卡
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("[00:01:24]")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.85))
                }
                Text("The key to futuristic financial agility is not just tracking, but understanding the narrative of your capital in real-time...")
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.70))
            }
            .liquidGlass(.regular, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.8)
            }

            // 当前实时激活高亮转写卡
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("[00:03:55]")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.85))

                    Spacer()

                    HStack(spacing: 6) {
                        smallPillTag("Translate")
                        smallPillTag("Live Summary")
                    }
                }

                HStack(alignment: .bottom, spacing: 2) {
                    Text("That's why we're focusing on highly fluid, transparent interfaces that feel almost alive, allowing us to connect with our users on a...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(irisViolet)
                        .lineLimit(3)

                    Rectangle()
                        .fill(irisViolet)
                        .frame(width: 2.0, height: 16)
                        .opacity(cursorVisible ? 1.0 : 0.2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            }
            .liquidGlass(.regular, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(irisViolet.opacity(0.35), lineWidth: 1.0)
            }
            .shadow(color: irisViolet.opacity(0.12), radius: 14, y: 6)
        }
    }

    private func smallPillTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.70))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6))
    }

    // MARK: - 3. 底部悬浮状态提示标签

    private var bottomStatusBadge: some View {
        HStack(spacing: 8) {
            Text(statusHint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.60) : Color.primary.opacity(0.55))

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
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(
                    scheme == .dark
                        ? Color(hex: "1F1235").opacity(0.50)
                        : Color.white.opacity(0.60)
                )
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.40), lineWidth: 0.6)
        }
    }

    // MARK: - 文本缺省与真实回退计算

    private var effectiveUserText: String {
        if let userQuery, !userQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userQuery
        }
        return "Can you analyze the quantum coherence of this model?"
    }

    private var effectiveAIText: String {
        if let aiResponse, !aiResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return aiResponse
        }
        return "Coherence is stable at 99.4%, initializing multi-agent reasoning..."
    }
}

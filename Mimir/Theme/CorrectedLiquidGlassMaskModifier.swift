import SwiftUI

// MARK: - 纯净 Alpha 遮罩与通透 Liquid Glass 修正修饰器
//
// 彻底根除浅色背景下的灰黑发脏与双重边框冲突：
// 1. 纯净 Alpha 遮罩：LinearGradient 只控制透明度，不参与表面颜色混合。
// 2. 纯净单层 Liquid Glass 卡片：去除多层 strokeBorder 嵌套，保证清透通透度与自适应高度。

// MARK: - 1. 纯净 Alpha 垂直双向渐隐遮罩

public struct CorrectedSoftVerticalFadeMaskModifier: ViewModifier {
    public var topFade: CGFloat
    public var bottomFade: CGFloat

    public init(topFade: CGFloat = 20, bottomFade: CGFloat = 50) {
        self.topFade = topFade
        self.bottomFade = bottomFade
    }

    public func body(content: Content) -> some View {
        content
            .mask(
                VStack(spacing: 0) {
                    // 顶部平滑淡入：从纯透明 (.clear) 到纯不透明 (.white)
                    LinearGradient(
                        colors: [Color.clear, Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(topFade, 1))

                    // 中间视口完全通透
                    Rectangle()
                        .fill(Color.white)

                    // 底部平滑渐隐：从纯不透明 (.white) 到纯透明 (.clear)
                    LinearGradient(
                        colors: [Color.white, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(bottomFade, 1))
                }
            )
    }
}

// MARK: - 3. 悬浮天气与日程胶囊（Floating Weather Capsule）

public struct FloatingWeatherAgendaCapsule: View {
    public var weatherText: String
    public var agendaText: String
    public var onTap: (() -> Void)?

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init(
        weatherText: String = "今天 晴 · 24°C",
        agendaText: String = "日程已同步",
        onTap: (() -> Void)? = nil
    ) {
        self.weatherText = weatherText
        self.agendaText = agendaText
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            Haptics.impact(.light)
            onTap?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.orange)

                Text(weatherText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppUI.label)

                Circle()
                    .fill(AppUI.separator)
                    .frame(width: 3.5, height: 3.5)

                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)

                Text(agendaText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppUI.label2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .liquidGlass(.regular, in: .capsule)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.55 : 0.85),
                                accent.opacity(scheme == .dark ? 0.35 : 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: accent.opacity(scheme == .dark ? 0.22 : 0.08), radius: 8, y: 2)
        }
        .buttonStyle(StaticButtonFeedbackStyle())
    }
}

extension View {
    /// 应用修复后的纯净 Alpha 垂直渐隐遮罩（杜绝脏底色）。
    public func correctedSoftFadeMask(topFade: CGFloat = 20, bottomFade: CGFloat = 50) -> some View {
        modifier(CorrectedSoftVerticalFadeMaskModifier(topFade: topFade, bottomFade: bottomFade))
    }

}

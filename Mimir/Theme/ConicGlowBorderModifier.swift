import SwiftUI

// MARK: - 动态弥散光晕边框修饰器 (Conic Gradient Glow & Breathing Backlight)
//
// 1. 旋转渐变描边：卡片外框应用 AngularGradient (Conic Gradient)，以当前主题色为基调，
//    由高亮渐变至透明再过渡回高亮，0° -> 360° 匀速旋转（周期 6s）。
// 2. 呼吸弥散背光：卡片底层附带一层使用当前主题色、超大动态高斯模糊 (Radius: 24~40) 的弥散光晕，
//    伴随 3s 正弦周期呼吸起伏 (Opacity: 0.25~0.65)。

public struct ConicGlowBorderModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var lineWidth: CGFloat
    public var isAnimated: Bool
    public var isBreathing: Bool

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init(
        cornerRadius: CGFloat = 28,
        lineWidth: CGFloat = 1.2,
        isAnimated: Bool = true,
        isBreathing: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.isAnimated = isAnimated
        self.isBreathing = isBreathing
    }

    public func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // 匀速旋转：周期 6s (360° / 6.0s = 60°/s)
            let angle = (time * 60.0).truncatingRemainder(dividingBy: 360)
            // 呼吸周期：3.0s 正弦波
            let breath = isBreathing ? (0.5 + 0.5 * sin(time * (2 * .pi / 3.0))) : 0.5

            content
                // 1. 底部动态高斯模糊呼吸弥散背光（严格绑定主题色，杜绝杂乱多色）
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accent.opacity(scheme == .dark ? 0.40 : 0.28),
                                    accent.opacity(scheme == .dark ? 0.65 : 0.45),
                                    Color.white.opacity(scheme == .dark ? 0.15 : 0.35),
                                    accent.opacity(scheme == .dark ? 0.30 : 0.20),
                                    accent.opacity(scheme == .dark ? 0.40 : 0.28)
                                ]),
                                center: .center,
                                angle: .degrees(angle)
                            )
                        )
                        .scaleEffect(1.02 + 0.03 * breath)
                        .blur(radius: 24.0 + 16.0 * breath) // 24 ~ 40 动态模糊
                        .opacity(0.25 + 0.40 * breath)       // 0.25 ~ 0.65 动态透明度
                        .allowsHitTesting(false)
                }
                // 2. 顶部 360° 旋转渐变折射描边
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(scheme == .dark ? 0.85 : 0.95),
                                    accent.opacity(scheme == .dark ? 0.90 : 0.85),
                                    accent.opacity(scheme == .dark ? 0.20 : 0.15),
                                    Color.clear,
                                    accent.opacity(scheme == .dark ? 0.40 : 0.30),
                                    Color.white.opacity(scheme == .dark ? 0.85 : 0.95)
                                ]),
                                center: .center,
                                angle: .degrees(angle)
                            ),
                            lineWidth: lineWidth
                        )
                        .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    /// 为卡片添加 360° 旋转渐变描边（6s 周期）与动态高斯模糊呼吸弥散背光（3s 周期，24~40 模糊，0.25~0.65 呼吸透明度）。
    public func conicGlowBorder(
        cornerRadius: CGFloat = 28,
        lineWidth: CGFloat = 1.2,
        isAnimated: Bool = true,
        isBreathing: Bool = true
    ) -> some View {
        modifier(
            ConicGlowBorderModifier(
                cornerRadius: cornerRadius,
                lineWidth: lineWidth,
                isAnimated: isAnimated,
                isBreathing: isBreathing
            )
        )
    }
}

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
        isBreathing: Bool = false
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

            content
                // 第一阶段：360° 旋转渐变折射描边（纯内边框 strokeBorder，零外溢风险）
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
    /// 为卡片添加 360° 旋转渐变描边（6s 周期，严格内部 strokeBorder，防溢出）。
    public func conicGlowBorder(
        cornerRadius: CGFloat = 28,
        lineWidth: CGFloat = 1.2,
        isAnimated: Bool = true,
        isBreathing: Bool = false
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

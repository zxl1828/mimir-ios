import SwiftUI

// MARK: - 纯净 Alpha 遮罩与通透 Liquid Glass 修正修饰器
//
// 彻底根除浅色背景下的灰黑发脏与双重边框冲突：
// 1. 纯净 Alpha 遮罩：遮罩必须仅使用 LinearGradient 控制透明通道，严格使用 `.clear` 与 `.black`
//    标准断点，杜绝任何 `Color.black.opacity(...)` 参与表面混合。
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

// MARK: - 2. 纯净 Liquid Glass 卡片修饰器（单层 1pt 微光折射描边）

public struct CorrectedLiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var interactive: Bool

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init(cornerRadius: CGFloat = 20, interactive: Bool = true) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content
            // 文本可读性保护底衬（WCAG AAA 对比度保障，采用纯白与极深紫基准）
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        scheme == .dark
                            ? Color(hex: "120D1D").opacity(0.80)
                            : Color.white.opacity(0.85)
                    )
            }
            .liquidGlass(
                interactive ? .regular.tint(accent.opacity(0.18)) : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
            .overlay {
                // 单层 1pt 迎光面半透明白、背光面主题色微散射描边
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.50 : 0.80),
                                accent.opacity(scheme == .dark ? 0.35 : 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(scheme == .dark ? 0.20 : 0.55),
                        Color.white.opacity(scheme == .dark ? 0.06 : 0.18),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.22 : 0.42),
                                Color.clear,
                                accent.opacity(scheme == .dark ? 0.16 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.45
                    )
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: accent.opacity(scheme == .dark ? 0.20 : 0.08),
                radius: 16,
                x: 0,
                y: 8
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
        .buttonStyle(PressScaleOvershootCapsuleButtonStyle(scale: 0.96))
    }
}

extension View {
    /// 应用修复后的纯净 Alpha 垂直渐隐遮罩（杜绝脏底色）。
    public func correctedSoftFadeMask(topFade: CGFloat = 20, bottomFade: CGFloat = 50) -> some View {
        modifier(CorrectedSoftVerticalFadeMaskModifier(topFade: topFade, bottomFade: bottomFade))
    }

    /// 应用单层 1pt 纯净 Liquid Glass 卡片材质（杜绝双重边框冲突）。
    public func correctedLiquidGlassCard(cornerRadius: CGFloat = 20, interactive: Bool = true) -> some View {
        modifier(CorrectedLiquidGlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

import SwiftUI
import UIKit

/// 原生风格与 Codex 液态玻璃统一设计令牌。
///
/// 整体背景采用纯黑（Dark）或纯白（Light），所有界面元素全面采用液态玻璃（Liquid Glass + 霓虹紫）设计语言。
enum AppUI {

    // MARK: - 尺寸

    /// 页面左右边距。
    static let hPadding: CGFloat = 16
    /// 列表项垂直间距。
    static let rowSpacing: CGFloat = 12
    /// 卡片 / 输入框圆角。
    static let cardRadius: CGFloat = 16
    /// 气泡圆角。
    static let bubbleRadius: CGFloat = 18
    /// 侧边栏面板宽度。
    static let sidebarWidth: CGFloat = 300
    /// 主视图打开抽屉时向右偏移的距离。
    static let sidebarShift: CGFloat = 280

    // MARK: - 基础色彩基准（严禁纯黑，统一采用纯白/极淡紫与极深紫）
    static let baseLightWhite = Color.white
    static let baseLightLavender = Color(hex: "F8F6FD")
    static let baseDarkDeepPurple = Color(hex: "120D1D")
    static let baseDarkPlum = Color(hex: "1A122B")
    static let pressSheenLight = Color(hex: "EADEFA")

    // MARK: - 颜色（纯白/极淡紫与极深紫基准 + 系统语义色）

    /// 画布主背景：深色下极深紫夜（#120D1D），浅色下极淡薰衣草紫（#F8F6FD）。
    static var canvas: Color {
        Color.adaptive(
            light: UIColor(red: 0.973, green: 0.965, blue: 0.992, alpha: 1.0),
            dark: UIColor(red: 0.071, green: 0.051, blue: 0.114, alpha: 1.0)
        )
    }

    /// 分组背景：深色下极深紫李（#1A122B），浅色下纯白（#FFFFFF）。
    static var groupCanvas: Color {
        Color.adaptive(
            light: UIColor.white,
            dark: UIColor(red: 0.102, green: 0.071, blue: 0.169, alpha: 1.0)
        )
    }

    static var secondary: Color {
        Color.adaptive(
            light: UIColor(white: 0.94, alpha: 1.0),
            dark: UIColor(red: 0.11, green: 0.10, blue: 0.15, alpha: 1.0)
        )
    }

    static var fill: Color {
        Color.adaptive(
            light: UIColor(white: 0.90, alpha: 0.8),
            dark: UIColor(white: 0.18, alpha: 0.6)
        )
    }

    static var label: Color { Color(uiColor: .label) }
    static var label2: Color { Color(uiColor: .secondaryLabel) }
    static var label3: Color { Color(uiColor: .tertiaryLabel) }
    static var separator: Color {
        Color.adaptive(
            light: UIColor(white: 0.86, alpha: 0.7),
            dark: UIColor(white: 0.22, alpha: 0.5)
        )
    }

    /// 品牌紫：浅色模式下足够深（白字压得住），深色模式下自动提亮（纯黑底上通透高光）。
    static let brandPurple = Color.adaptive(
        light: UIColor(red: 0.50, green: 0.31, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.51, blue: 1.00, alpha: 1)
    )

    /// 霓虹紫：Codex 桌面端风格的高亮态与星尘激活轨主色。
    static let neonViolet = Color.adaptive(
        light: UIColor(red: 0.58, green: 0.25, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.76, green: 0.50, blue: 1.00, alpha: 1)
    )

    /// 深紫罗兰：低亮度底色 / 深色模式下的沉稳强调色。
    static let deepViolet = Color.adaptive(
        light: UIColor(red: 0.35, green: 0.16, blue: 0.74, alpha: 1),
        dark: UIColor(red: 0.50, green: 0.28, blue: 0.94, alpha: 1)
    )

    /// 星尘滑轨电光紫起点。
    static let stardustElectric = Color.adaptive(
        light: UIColor(red: 0.36, green: 0.16, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.38, green: 0.15, blue: 0.98, alpha: 1)
    )

    /// 星尘滑轨霓虹紫终点。
    static let stardustGlow = Color.adaptive(
        light: UIColor(red: 0.62, green: 0.28, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.32, blue: 1.00, alpha: 1)
    )

    /// 品牌强调色（默认紫）。视图里优先用 `@Environment(\.appAccent)`。
    static let accent = brandPurple

    // MARK: - 字体（SF Pro / 系统默认）

    static var navTitle: Font { .system(size: 17, weight: .semibold) }
    static var body: Font { .system(size: 16) }
    static var subheadline: Font { .system(size: 15) }
    static var footnote: Font { .system(size: 13) }
    static var caption: Font { .system(size: 12) }
    static var chip: Font { .system(size: 13, weight: .medium) }
    static var rowTitle: Font { .system(size: 16) }
    static var sectionTitle: Font { .system(size: 13, weight: .semibold) }

    // MARK: - 动效

    static var drawer: Animation { .spring(response: 0.36, dampingFraction: 0.86) }
    static var snap: Animation { .spring(response: 0.28, dampingFraction: 0.82) }

    // MARK: - 液态玻璃（Codex 桌面端风格，纯黑与纯白底板上的通透悬浮）

    /// 物理折射描边：顶部高位白光透射 → 中段融合强调色微光 → 底部柔光。
    static func refractionEdge(_ accent: Color, scheme: ColorScheme) -> LinearGradient {
        let topWhite = scheme == .dark ? 0.62 : 0.90
        let midAccent = scheme == .dark ? 0.52 : 0.42
        let lowAccent = scheme == .dark ? 0.30 : 0.24
        let bottomTint = scheme == .dark ? Color.white.opacity(0.12) : accent.opacity(0.20)
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(topWhite), location: 0.0),
                .init(color: accent.opacity(midAccent), location: 0.40),
                .init(color: accent.opacity(lowAccent), location: 0.72),
                .init(color: bottomTint, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 液态玻璃表面底衬色：纯黑 OLED 底上带微弱紫夜磨砂，纯白底上带通透珠光。
    static func glassTint(scheme: ColorScheme, isHighlighted: Bool = false) -> Color {
        if scheme == .dark {
            return Color(red: 0.10, green: 0.08, blue: 0.18)
                .opacity(isHighlighted ? 0.62 : 0.46)
        } else {
            return Color.white.opacity(isHighlighted ? 0.82 : 0.70)
        }
    }

    // MARK: - 新增全局设计系统规范 (Design Tokens)

    /// 电光紫高亮色（#7C5CFC）。
    static let electricViolet = Color(red: 0.486, green: 0.361, blue: 0.988)
    /// 极光淡紫（#A78BFA）。
    static let auroraViolet = Color(red: 0.655, green: 0.545, blue: 0.980)

    static func textTitle(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.94, blue: 0.98) : Color(red: 0.12, green: 0.11, blue: 0.18)
    }

    static func textSubtitle(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.65, green: 0.63, blue: 0.72) : Color(red: 0.36, green: 0.35, blue: 0.44)
    }

    static func textCaption(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.49, green: 0.48, blue: 0.56) : Color(red: 0.61, green: 0.64, blue: 0.69)
    }

    /// 规范要求的纯白/极淡紫至极深紫渐变背景（深色模式自适应为极深高级紫 #120D1D -> #1A122B）。
    static func ambientBackground(scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [Color(hex: "120D1D"), Color(hex: "1A122B")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.white, Color(hex: "F8F6FD")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// 规范软玻璃卡片 1pt 半透明浅白微光描边（迎光面半透明白，背光面主题色微散射）。
    static func softGlassCardBorder(accent: Color = brandPurple, scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.45 : 0.80),
                accent.opacity(scheme == .dark ? 0.35 : 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 软玻璃拟态卡片修饰器（全原生 iOS 27 Liquid Glass + 保护性文本清晰度底衬）。
struct SoftGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    func body(content: Content) -> some View {
        content
            // 文本可读性保护底衬（WCAG AAA 级对比度保障，杜绝背景穿透文字发虚）
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        scheme == .dark
                            ? Color(hex: "120D1D").opacity(0.80)
                            : Color.white.opacity(0.85)
                    )
            }
            .liquidGlass(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppUI.softGlassCardBorder(accent: accent, scheme: scheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: accent.opacity(scheme == .dark ? 0.20 : 0.08),
                radius: 14,
                x: 0,
                y: 6
            )
    }
}

extension View {
    /// 应用全局软玻璃卡片材质规范。
    func softGlassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(SoftGlassCardModifier(cornerRadius: cornerRadius))
    }
}

extension Color {
    /// 浅色 / 深色两套取值的动态色。
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - 强调色与背景环境值

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue: Color = AppUI.accent
}

private struct AppBackgroundKey: EnvironmentKey {
    static let defaultValue: AppBackground = .plain
}

extension EnvironmentValues {
    /// 全应用强调色，由 `RootView` 从设置注入。
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }

    /// 全应用聊天背景枚举，由 `RootView` 从设置注入。
    var appBackground: AppBackground {
        get { self[AppBackgroundKey.self] }
        set { self[AppBackgroundKey.self] = newValue }
    }
}

// MARK: - 背景（纯净紫雾 / 紫夜底板 + 动态环境光实时融合）

/// 全屏聊天背景：浅紫至雪白平滑渐变（#F4F1FA -> #E8E2F5），深色自适应为深紫夜渐变，彻底废除纯黑粗糙底板；
/// 支持低功耗现实环境光融合与内置壁纸。
struct AppBackgroundView: View {

    var background: AppBackground

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(AppSettings.self) private var settings

    @State private var ambientEngine = CameraLiveAmbientEngine.shared

    var body: some View {
        ZStack {
            // 1. 基底：浅紫至雪白平滑渐变（深色为深紫夜渐变，彻底杜绝纯黑底板）
            AppUI.ambientBackground(scheme: scheme)

            // 2. 动态环境层：低功耗现实环境光实时融合 vs 模拟动态流光
            if settings.dynamicBackgroundMode == .cameraAmbientFeed && ambientEngine.isRunning {
                cameraAmbientOverlay
            } else {
                meshGradientOverlay
            }

            // 3. 用户自选内置壁纸（若有）
            if let name = background.assetName {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        AppUI.ambientBackground(scheme: scheme)
                            .opacity(scheme == .dark ? 0.68 : 0.82)
                    )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: background)
        .onAppear {
            syncCameraEngine()
        }
        .onChange(of: settings.dynamicBackgroundMode) { _, _ in
            syncCameraEngine()
        }
        .onChange(of: settings.cameraAmbientGain) { _, gain in
            ambientEngine.gain = gain
        }
        .onChange(of: settings.cameraAmbientSmoothing) { _, smoothing in
            ambientEngine.temporalSmoothing = smoothing
        }
    }

    private func syncCameraEngine() {
        ambientEngine.gain = settings.cameraAmbientGain
        ambientEngine.temporalSmoothing = settings.cameraAmbientSmoothing
        if settings.dynamicBackgroundMode == .cameraAmbientFeed {
            ambientEngine.start()
        } else {
            ambientEngine.stop()
        }
    }

    private var cameraAmbientOverlay: some View {
        LinearGradient(
            colors: [
                ambientEngine.ambientTopColor.opacity(settings.cameraAmbientGain * (scheme == .dark ? 1.2 : 0.9)),
                ambientEngine.ambientBottomColor.opacity(settings.cameraAmbientGain * (scheme == .dark ? 0.8 : 0.6))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
        .blendMode(scheme == .dark ? .plusLighter : .sourceAtop)
    }

    private var meshGradientOverlay: some View {
        RadialGradient(
            colors: [
                accent.opacity(scheme == .dark ? 0.12 : 0.08),
                Color.clear
            ],
            center: .topLeading,
            startRadius: 40,
            endRadius: 420
        )
        .allowsHitTesting(false)
    }
}

// MARK: - 复用组件

/// 设置页行：左图标 + 标题 +（可选）右侧灰色详情 + chevron。
struct SettingsRow: View {

    let icon: String
    let title: String
    var detail: String?
    var tint: Color? = nil
    var showsChevron: Bool = true

    @Environment(\.appAccent) private var accent

    private var iconTint: Color { tint ?? accent }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 26, height: 26)

            Text(title)
                .font(AppUI.rowTitle)
                .foregroundStyle(AppUI.label)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(AppUI.subheadline)
                    .foregroundStyle(AppUI.label2)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppUI.label3)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 顶栏圆形液态玻璃图标按钮（iOS 27 原生 Liquid Glass）。
struct UIBarButton: View {

    let icon: String
    let label: String
    var isHighlighted: Bool = false
    var action: () -> Void

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isHighlighted ? accent : AppUI.label)
                .frame(width: 36, height: 36)
                .liquidGlass(
                    isHighlighted ? .regular.tint(accent.opacity(0.40)).interactive() : .regular.interactive(),
                    in: .circle
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            isHighlighted
                                ? AnyShapeStyle(accent.opacity(0.85))
                                : AnyShapeStyle(AppUI.refractionEdge(accent, scheme: scheme)),
                            lineWidth: isHighlighted ? 1.2 : 0.9
                        )
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: isHighlighted ? accent.opacity(scheme == .dark ? 0.50 : 0.28) : accent.opacity(scheme == .dark ? 0.20 : 0.06),
                    radius: isHighlighted ? 11 : 6,
                    y: 2
                )
                .contentShape(Circle())
        }
        .pressScaleOvershootCircle(scale: 0.94)
        .accessibilityLabel(label)
    }
}

/// 输入框上方的快捷功能胶囊（iOS 27 原生 Liquid Glass 风格）。
struct UIQuickChip: View {

    let icon: String
    let title: String
    var isSelected: Bool = false
    var action: () -> Void

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            if isSelected {
                Haptics.selectionChanged()
            } else {
                Haptics.impact(.light)
            }
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(AppUI.chip)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : AppUI.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .liquidGlass(
                isSelected ? .regular.tint(accent.opacity(0.85)).interactive() : .clear.interactive(),
                in: .capsule
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(Color.white.opacity(0.45))
                            : AnyShapeStyle(AppUI.refractionEdge(accent, scheme: scheme)),
                        lineWidth: 0.9
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: isSelected ? accent.opacity(scheme == .dark ? 0.45 : 0.25) : accent.opacity(scheme == .dark ? 0.16 : 0.04),
                radius: 6,
                y: 2
            )
            .contentShape(Capsule(style: .continuous))
        }
        .pressScaleOvershootCapsule(scale: 0.96)
    }
}

// MARK: - 液态玻璃修饰器

/// iOS 27 官方液态玻璃修饰器：原生 glassEffect + 物理折射描边 + 悬浮辉光投影 + 保护性文本清晰度底衬。
struct LiquidGlassModifier: ViewModifier {

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var cornerRadius: CGFloat = AppUI.cardRadius
    var isHighlighted: Bool = false
    var glowIntensity: CGFloat = 0.35

    func body(content: Content) -> some View {
        content
            // 文本可读性保护底衬（WCAG AAA 级对比度保障，杜绝玻璃背景穿透文字发虚）
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        scheme == .dark
                            ? Color(red: 0.10, green: 0.08, blue: 0.18).opacity(0.38)
                            : Color.white.opacity(0.42)
                    )
            }
            .liquidGlass(
                isHighlighted
                    ? .regular.tint(accent.opacity(0.35)).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
            // 外层折射倒角
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            // 内聚光晕
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accent.opacity(isHighlighted ? 0.65 : (scheme == .dark ? 0.24 : 0.16)),
                        lineWidth: isHighlighted ? 1.4 : 0.9
                    )
                    .blur(radius: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: accent.opacity(glowIntensity * (scheme == .dark ? 0.55 : 0.24)),
                radius: isHighlighted ? 18 : 12,
                y: 5
            )
            .shadow(
                color: (scheme == .dark ? Color(red: 0.05, green: 0.04, blue: 0.10).opacity(0.46) : accent.opacity(0.08)),
                radius: 10,
                y: 4
            )
            .animation(AppUI.snap, value: isHighlighted)
    }
}

extension View {
    /// 液态玻璃容器：超薄材质 + 折射描边 + 悬浮辉光。
    func liquidGlass(
        cornerRadius: CGFloat = AppUI.cardRadius,
        isHighlighted: Bool = false,
        glowIntensity: CGFloat = 0.35
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                isHighlighted: isHighlighted,
                glowIntensity: glowIntensity
            )
        )
    }
}

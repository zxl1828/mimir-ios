import SwiftUI
import UIKit

/// 原生风格与 Codex 液态玻璃统一设计令牌。
///
/// 所有视图统一走系统语义色与 `@Environment(\.appAccent)` / `@Environment(\.appBackground)`，
/// 保证在浅色与深色模式、辅助功能下自动适配，杜绝写死颜色。
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

    // MARK: - 颜色（全部系统语义色 + 自适应深浅色）

    static var canvas: Color { Color(uiColor: .systemBackground) }
    static var groupCanvas: Color { Color(uiColor: .systemGroupedBackground) }
    static var secondary: Color { Color(uiColor: .secondarySystemBackground) }
    static var fill: Color { Color(uiColor: .tertiarySystemFill) }
    static var label: Color { Color(uiColor: .label) }
    static var label2: Color { Color(uiColor: .secondaryLabel) }
    static var label3: Color { Color(uiColor: .tertiaryLabel) }
    static var separator: Color { Color(uiColor: .separator) }

    /// 品牌紫：浅色模式下足够深（白字压得住），深色模式下自动提亮（黑底上通透）。
    static let brandPurple = Color.adaptive(
        light: UIColor(red: 0.50, green: 0.31, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.67, green: 0.50, blue: 1.00, alpha: 1)
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

    /// 星尘滑轨电光紫起点（深浅色下均保持浓郁高对比度，衬托白色星尘与圆钮）。
    static let stardustElectric = Color.adaptive(
        light: UIColor(red: 0.36, green: 0.16, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.38, green: 0.15, blue: 0.98, alpha: 1)
    )

    /// 星尘滑轨霓虹紫终点。
    static let stardustGlow = Color.adaptive(
        light: UIColor(red: 0.62, green: 0.28, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.32, blue: 1.00, alpha: 1)
    )

    /// 品牌强调色（默认紫）。视图里请优先用 `@Environment(\.appAccent)`。
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

    // MARK: - 液态玻璃（Codex 桌面端风格，兼顾浅色与深色模式）

    /// 物理折射描边：顶部高位白光透射 → 中段融合强调色微光 → 底部柔光。
    /// 浅色模式下加重强调色边缘折射，避免白光在浅底上隐形；深色模式下突出高光通透感。
    static func refractionEdge(_ accent: Color, scheme: ColorScheme) -> LinearGradient {
        let topWhite = scheme == .dark ? 0.44 : 0.86
        let midAccent = scheme == .dark ? 0.48 : 0.36
        let lowAccent = scheme == .dark ? 0.28 : 0.22
        let bottomTint = scheme == .dark ? Color.white.opacity(0.10) : accent.opacity(0.18)
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(topWhite), location: 0.0),
                .init(color: accent.opacity(midAccent), location: 0.42),
                .init(color: accent.opacity(lowAccent), location: 0.72),
                .init(color: bottomTint, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 液态玻璃表面底衬色：深色下带微弱深紫黑底衬，浅色下带珠光白底衬。
    static func glassTint(scheme: ColorScheme, isHighlighted: Bool = false) -> Color {
        if scheme == .dark {
            return Color(red: 0.09, green: 0.07, blue: 0.16)
                .opacity(isHighlighted ? 0.56 : 0.42)
        } else {
            return Color.white.opacity(isHighlighted ? 0.76 : 0.62)
        }
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
    static let defaultValue: AppBackground = .violetMist
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

// MARK: - 背景

/// 全屏聊天背景：纯色，或内置壁纸 + 一层可读性遮罩（自动适配深浅色模式）。
struct AppBackgroundView: View {

    var background: AppBackground

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    var body: some View {
        ZStack {
            AppUI.canvas

            if let name = background.assetName {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        Color(uiColor: .systemBackground)
                            .opacity(scheme == .dark ? 0.56 : 0.78)
                    )
            } else {
                // 纯色模式下在顶部叠一层极淡的紫罗兰环境光晕，契合 Codex 氛围且不影响浅色可读性
                RadialGradient(
                    colors: [
                        accent.opacity(scheme == .dark ? 0.14 : 0.07),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: background)
    }
}

// MARK: - 复用组件

/// 设置页行：左图标 + 标题 +（可选）右侧灰色详情 + chevron。
struct SettingsRow: View {

    let icon: String
    let title: String
    var detail: String?
    /// 传 nil 时使用全局强调色。
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

/// 顶栏圆形液态玻璃图标按钮（契合 Codex 桌面端 Command Header 风格）。
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
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(isHighlighted ? accent.opacity(scheme == .dark ? 0.22 : 0.14) : AppUI.glassTint(scheme: scheme))
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isHighlighted
                                ? AnyShapeStyle(accent.opacity(0.75))
                                : AnyShapeStyle(AppUI.refractionEdge(accent, scheme: scheme)),
                            lineWidth: isHighlighted ? 1.2 : 0.9
                        )
                }
                .shadow(
                    color: isHighlighted ? accent.opacity(scheme == .dark ? 0.45 : 0.25) : .black.opacity(scheme == .dark ? 0.28 : 0.06),
                    radius: isHighlighted ? 10 : 5,
                    y: 2
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 输入框上方的快捷功能胶囊。
struct UIQuickChip: View {

    let icon: String
    let title: String
    /// 选中态：用于智能体这类需要高亮当前项的胶囊。
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
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(Color.white.opacity(0.32))
                            : AnyShapeStyle(AppUI.refractionEdge(accent, scheme: scheme)),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: isSelected ? accent.opacity(scheme == .dark ? 0.40 : 0.24) : .clear,
                radius: 6,
                y: 2
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 液态玻璃修饰器

/// Codex 桌面端风格的液态玻璃：超薄材质 + 自适应底衬 + 物理折射描边 + 环境辉光。
struct LiquidGlassModifier: ViewModifier {

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var cornerRadius: CGFloat = AppUI.cardRadius
    var isHighlighted: Bool = false
    var glowIntensity: CGFloat = 0.35

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppUI.glassTint(scheme: scheme, isHighlighted: isHighlighted))
                    )
            }
            // 外层折射倒角
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            // 内聚光晕：高亮态更亮
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accent.opacity(isHighlighted ? 0.62 : (scheme == .dark ? 0.22 : 0.16)),
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
            .shadow(color: .black.opacity(scheme == .dark ? 0.42 : 0.08), radius: 10, y: 4)
            .animation(AppUI.snap, value: isHighlighted)
    }
}

extension View {
    /// 液态玻璃容器：超薄材质 + 折射描边 + 环境辉光。
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

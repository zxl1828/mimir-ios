import SwiftUI
import UIKit

/// 原生风格设计令牌（v2 UI）。
///
/// 与 `AppColor` / `GlassStyles` 的液态玻璃体系并存：新 UI 一律走系统语义色，
/// 保证在深浅色、辅助功能下自动适配，不再依赖自定义材质。
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

    // MARK: - 颜色（全部系统语义色）

    static var canvas: Color { Color(uiColor: .systemBackground) }
    static var groupCanvas: Color { Color(uiColor: .systemGroupedBackground) }
    static var secondary: Color { Color(uiColor: .secondarySystemBackground) }
    static var fill: Color { Color(uiColor: .tertiarySystemFill) }
    static var label: Color { Color(uiColor: .label) }
    static var label2: Color { Color(uiColor: .secondaryLabel) }
    static var label3: Color { Color(uiColor: .tertiaryLabel) }
    static var separator: Color { Color(uiColor: .separator) }
    /// 品牌紫：浅色模式下足够深（白字压得住），深色模式下自动提亮（黑底上不糊）。
    static let brandPurple = Color.adaptive(
        light: UIColor(red: 0.52, green: 0.36, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.52, blue: 1.00, alpha: 1)
    )

    /// 霓虹紫：黑底上最"发光"的一档，用于 Codex 风格的高亮态。
    static let neonViolet = Color.adaptive(
        light: UIColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.75, green: 0.52, blue: 1.00, alpha: 1)
    )

    /// 深紫罗兰：低亮度底色 / 深色模式下的沉稳强调色。
    static let deepViolet = Color.adaptive(
        light: UIColor(red: 0.36, green: 0.16, blue: 0.72, alpha: 1),
        dark: UIColor(red: 0.52, green: 0.32, blue: 0.95, alpha: 1)
    )

    /// 品牌强调色（默认紫）。视图里请优先用 `@Environment(\.appAccent)`，
    /// 这样设置里换强调色才能全局生效；这里只作为环境默认值。
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

    // MARK: - 液态玻璃（Codex 桌面端风格）

    /// 折射描边：顶部高位白光 → 中段融合强调色微光 → 底部弱光。
    /// 深色下白光更弱、强调色更亮，黑底上才有"通透悬浮"感。
    static func refractionEdge(_ accent: Color, scheme: ColorScheme) -> LinearGradient {
        let topWhite = scheme == .dark ? 0.40 : 0.70
        let bottomWhite = scheme == .dark ? 0.08 : 0.26
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(topWhite), location: 0.0),
                .init(color: accent.opacity(scheme == .dark ? 0.45 : 0.30), location: 0.42),
                .init(color: accent.opacity(scheme == .dark ? 0.28 : 0.16), location: 0.68),
                .init(color: Color.white.opacity(bottomWhite), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

// MARK: - 强调色环境值

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue: Color = AppUI.accent
}

extension EnvironmentValues {
    /// 全应用强调色，由 `RootView` 从设置注入。
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

// MARK: - 背景

/// 全屏聊天背景：纯色，或内置壁纸 + 一层可读性遮罩。
struct AppBackgroundView: View {

    var background: AppBackground

    @Environment(\.colorScheme) private var scheme

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
                            .opacity(scheme == .dark ? 0.58 : 0.76)
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

/// 顶栏圆形图标按钮（无背景，点击反馈靠 haptics）。
struct UIBarButton: View {

    let icon: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppUI.label)
                .frame(width: 36, height: 36)
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
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.thinMaterial))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 液态玻璃修饰器

/// Codex 桌面端风格的液态玻璃：超薄材质 + 物理折射描边 + 环境辉光。
///
/// 与 `GlassStyles` 里基于系统 `glassEffect` 的旧写法并存——新组件统一用它，
/// 旧页面不受影响。
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
            }
            // 外层折射倒角
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
            }
            // 内聚光晕：高亮态更亮
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accent.opacity(isHighlighted ? 0.55 : 0.20),
                        lineWidth: isHighlighted ? 1.4 : 1
                    )
                    .blur(radius: 0.6)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: accent.opacity(glowIntensity * (scheme == .dark ? 0.55 : 0.28)),
                radius: isHighlighted ? 18 : 12,
                y: 5
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.42 : 0.10), radius: 10, y: 4)
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

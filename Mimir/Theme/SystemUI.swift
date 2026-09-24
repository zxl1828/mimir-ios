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
    static let accent = Color.blue

    /// 滑块轨道渐变：蓝 → 紫。
    static var levelGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color(red: 0.55, green: 0.32, blue: 0.98)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

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
}

// MARK: - 复用组件

/// 设置页行：左图标 + 标题 +（可选）右侧灰色详情 + chevron。
struct SettingsRow: View {

    let icon: String
    let title: String
    var detail: String?
    var tint: Color = AppUI.accent
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
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
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(AppUI.chip)
            }
            .foregroundStyle(AppUI.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(AppUI.secondary))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 底部 Sheet 顶部的灰色拖拽条。
struct SheetGrabber: View {

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color(uiColor: .systemGray4))
            .frame(width: 40, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

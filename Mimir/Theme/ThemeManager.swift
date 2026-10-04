import SwiftUI
import Observation

/// 全局动态主题管理器（Reactive Theme Manager）。
///
/// 统一管理应用外观模式（Appearance）、强调色（Accent）与背景（Background），
/// 并为全应用所有液态玻璃（Liquid Glass）、粒子、高光、描边与阴影提供同色系微阶渐变（Monochromatic Harmony），
/// 严禁任何硬编码静态颜色，确保浅色与深色模式下自适应与高对比可读性。
@Observable
final class ThemeManager: @unchecked Sendable {

    static let shared = ThemeManager()

    var accent: AppAccent = .purple
    var appearance: AppAppearance = .system
    var background: AppBackground = .plain

    var primaryColor: Color {
        accent.color
    }

    func sync(with accent: AppAccent) {
        self.accent = accent
    }

    /// 高光主光晕色（自动根据深浅色调整透明度）
    func surfaceGlow(scheme: ColorScheme) -> Color {
        accent.color.opacity(scheme == .dark ? 0.38 : 0.20)
    }

    /// 微光边缘渐变（迎光面为半透明白色高光，背光面为当前主题色的微散射）
    func borderGradient(scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.45 : 0.85),
                accent.color.opacity(scheme == .dark ? 0.40 : 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 思考滑块与流光轨道的同色系微阶渐变
    var trackGradient: LinearGradient {
        LinearGradient(
            colors: [
                accent.color.opacity(0.85),
                accent.color,
                accent.color.opacity(0.65)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 单色系微阶颜色（用于粒子与背景微斑）
    func shade(opacity: Double) -> Color {
        accent.color.opacity(opacity)
    }

    /// 流水焦散流光（Fluid Caustics Sheen）
    func causticsGradient(scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.35 : 0.50),
                accent.color.opacity(scheme == .dark ? 0.25 : 0.28),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager = ThemeManager.shared
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

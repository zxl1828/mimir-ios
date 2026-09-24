import SwiftUI

/// 全局配色。
///
/// 设计原则：品牌色使用固定值（在深色 / 浅色模式下都有足够对比度），
/// 背景与文字使用系统语义色，从而自动适配深色模式与辅助功能设置。
enum AppColor {

    // MARK: - 品牌

    static let brandIndigo = Color(red: 0.36, green: 0.35, blue: 0.98)
    static let brandBlue = Color(red: 0.25, green: 0.52, blue: 1.00)
    static let brandPurple = Color(red: 0.62, green: 0.34, blue: 0.98)
    static let brandTeal = Color(red: 0.16, green: 0.74, blue: 0.76)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [brandIndigo, brandBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradientSoft: LinearGradient {
        LinearGradient(
            colors: [brandIndigo.opacity(0.85), brandPurple.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - 表面

    static var canvas: Color { Color(uiColor: .systemBackground) }
    static var elevated: Color { Color(uiColor: .secondarySystemBackground) }
    static var subtle: Color { Color(uiColor: .tertiarySystemBackground) }
    static var separator: Color { Color(uiColor: .separator) }

    // MARK: - 文字

    static var primaryText: Color { Color(uiColor: .label) }
    static var secondaryText: Color { Color(uiColor: .secondaryLabel) }
    static var tertiaryText: Color { Color(uiColor: .tertiaryLabel) }

    // MARK: - 语义

    static let success = Color(red: 0.20, green: 0.78, blue: 0.42)
    static let warning = Color(red: 0.98, green: 0.68, blue: 0.20)
    static let danger = Color(red: 0.96, green: 0.30, blue: 0.33)

    // MARK: - 语音模式

    static let listening = Color(red: 0.20, green: 0.72, blue: 0.98)
    static let thinking = Color(red: 0.62, green: 0.40, blue: 0.98)
    static let speaking = Color(red: 0.16, green: 0.80, blue: 0.66)
    static let interrupted = Color(red: 1.00, green: 0.62, blue: 0.24)
}

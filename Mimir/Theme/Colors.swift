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

    // MARK: - 思考档位（冷 → 暖插值端点）

    static let thinkingCold = Color(red: 0.25, green: 0.60, blue: 1.00)
    static let thinkingMid = Color(red: 0.55, green: 0.42, blue: 0.98)
    static let thinkingWarm = Color(red: 1.00, green: 0.52, blue: 0.28)

    /// 档位色：由冷到暖连续插值，供滑块填充与指示器着色。
    static func thinkingTint(for mode: ThinkingMode) -> Color {
        switch mode {
        case .quick: return thinkingCold
        case .thinking: return Color(red: 0.38, green: 0.52, blue: 0.99)
        case .expert: return thinkingMid
        case .ultra: return thinkingWarm
        }
    }

    /// 滑块轨道填充：按 0...1 位置在两段渐变之间插值。
    static func thinkingTrackColor(progress: Double) -> Color {
        let t = min(max(progress, 0), 1)
        if t < 0.5 {
            return blend(thinkingCold, thinkingMid, amount: t * 2)
        } else {
            return blend(thinkingMid, thinkingWarm, amount: (t - 0.5) * 2)
        }
    }

    static func blend(_ from: Color, _ to: Color, amount: Double) -> Color {
        let a = min(max(amount, 0), 1)
        let f = UIColor(from).rgba
        let t = UIColor(to).rgba
        return Color(
            red: f.r + (t.r - f.r) * a,
            green: f.g + (t.g - f.g) * a,
            blue: f.b + (t.b - f.b) * a,
            opacity: f.a + (t.a - f.a) * a
        )
    }

    // MARK: - 语音模式

    static let listening = Color(red: 0.20, green: 0.72, blue: 0.98)
    static let thinking = Color(red: 0.62, green: 0.40, blue: 0.98)
    static let speaking = Color(red: 0.16, green: 0.80, blue: 0.66)
    static let interrupted = Color(red: 1.00, green: 0.62, blue: 0.24)
}

extension UIColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

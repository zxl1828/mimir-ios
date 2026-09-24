import SwiftUI

/// 字体与文本样式。正文走系统默认字体（中文可读性最佳），
/// 标题与数字走圆角设计（更接近原生 App 的观感）。
enum AppFont {

    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static var bubbleBody: Font { .system(size: 16.5) }
    static var sidebarSection: Font { .system(size: 12, weight: .semibold) }
    static var sidebarRow: Font { .system(size: 15.5) }
    static var chip: Font { .system(size: 13.5, weight: .medium) }
    static var chipCompact: Font { .system(size: 12.5, weight: .medium) }
    static var caption: Font { .system(size: 12) }
    static var hint: Font { .system(size: 12.5) }
    static var onboardingField: Font { .system(size: 16) }
    static var button: Font { .system(size: 17, weight: .semibold) }
    static var code: Font { .system(size: 13.5, design: .monospaced) }
    static var codeSmall: Font { .system(size: 12, design: .monospaced) }
    static var metric: Font { .system(size: 22, weight: .semibold, design: .rounded) }
}

/// 统一的间距刻度，避免各视图随手写数字导致节奏不一致。
enum AppSpacing {
    static let hairline: CGFloat = 2
    static let tight: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let section: CGFloat = 32
    static let cardCorner: CGFloat = 20
    static let chipCorner: CGFloat = 18
}

import SwiftUI

/// 外观模式：跟随系统 / 浅色 / 深色。
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// nil 表示交给系统决定。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 强调色：全应用统一使用的系统色板。
enum AppAccent: String, CaseIterable, Identifiable, Sendable {

    case purple
    case neon
    case deepViolet
    case indigo
    case blue
    case pink
    case orange
    case green
    case teal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purple: "紫色"
        case .neon: "霓虹紫"
        case .deepViolet: "深紫罗兰"
        case .indigo: "靛蓝"
        case .blue: "蓝色"
        case .pink: "粉色"
        case .orange: "橙色"
        case .green: "绿色"
        case .teal: "青色"
        }
    }

    var color: Color {
        switch self {
        case .purple: AppUI.brandPurple
        case .neon: AppUI.neonViolet
        case .deepViolet: AppUI.deepViolet
        case .indigo: .indigo
        case .blue: .blue
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        }
    }
}

/// 聊天背景：纯色（系统背景）或内置壁纸。
///
/// 壁纸由 `tools/generate_wallpapers.py` 生成，故意压成低对比度，
/// 上层再叠一层系统背景色遮罩，保证正文始终可读。
enum AppBackground: String, CaseIterable, Identifiable, Sendable {

    case plain
    case violetMist
    case aurora
    case starfield

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "纯色"
        case .violetMist: "紫雾"
        case .aurora: "极光"
        case .starfield: "星夜"
        }
    }

    /// Asset catalog 里的图片名；纯色没有图片。
    var assetName: String? {
        switch self {
        case .plain: nil
        case .violetMist: "bg-violet-mist"
        case .aurora: "bg-aurora"
        case .starfield: "bg-starfield"
        }
    }
}

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

    case blue
    case indigo
    case purple
    case pink
    case orange
    case green
    case teal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "蓝色"
        case .indigo: "靛蓝"
        case .purple: "紫色"
        case .pink: "粉色"
        case .orange: "橙色"
        case .green: "绿色"
        case .teal: "青色"
        }
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        }
    }
}

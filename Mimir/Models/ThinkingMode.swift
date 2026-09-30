import Foundation

/// 思考程度。左 → 右：High / Extra High / Max (Ultra)。
///
/// 三档**全部带思考**——不再提供"几乎不思考"的最低档，默认就是 High。
/// 档位同时驱动星尘阶梯滑块的视觉表现与发送请求时的模型参数。
enum ThinkingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case thinking
    case expert
    case ultra

    var id: String { rawValue }

    /// 紧凑徽标名（High / X-High / Max）。
    var title: String {
        switch self {
        case .thinking: return "High"
        case .expert: return "X-High"
        case .ultra: return "Max"
        }
    }

    /// 浮动卡片大标题与状态胶囊后缀（与实机参考图 Ultra 对齐）。
    var heroTitle: String {
        switch self {
        case .thinking: return "High"
        case .expert: return "X-High"
        case .ultra: return "Ultra"
        }
    }

    // MARK: - 模型参数映射

    var temperature: Double {
        switch self {
        case .thinking: return 0.60
        case .expert: return 0.45
        case .ultra: return 0.30
        }
    }

    var maxTokens: Int {
        switch self {
        case .thinking: return 4_096
        case .expert: return 8_192
        case .ultra: return 16_384
        }
    }
}

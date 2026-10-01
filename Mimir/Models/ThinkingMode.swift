import Foundation

/// 思考程度。左 → 右：Light / High / Extra High / Max (Ultra)。
///
/// 四档**全部带思考**——不再提供"不思考"的模式，全部档位均执行推理。
/// 档位同时驱动星尘阶梯滑块的视觉表现与发送请求时的模型参数。
enum ThinkingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case thinking
    case expert
    case ultra

    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "light", "quick":
            self = .light
        case "thinking":
            self = .thinking
        case "expert":
            self = .expert
        case "ultra":
            self = .ultra
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "quick" || raw == "light" {
            self = .light
        } else if let mode = ThinkingMode(rawValue: raw) {
            self = mode
        } else {
            self = .thinking
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// 紧凑徽标名（Light / High / X-High / Max）。
    var title: String {
        switch self {
        case .light: return "Light"
        case .thinking: return "High"
        case .expert: return "X-High"
        case .ultra: return "Max"
        }
    }

    /// 浮动卡片大标题与状态胶囊后缀（与实机参考图 Ultra 对齐）。
    var heroTitle: String {
        switch self {
        case .light: return "Light"
        case .thinking: return "High"
        case .expert: return "X-High"
        case .ultra: return "Ultra"
        }
    }

    // MARK: - 模型参数映射

    var temperature: Double {
        switch self {
        case .light: return 0.70
        case .thinking: return 0.60
        case .expert: return 0.45
        case .ultra: return 0.30
        }
    }

    var maxTokens: Int {
        switch self {
        case .light: return 2_048
        case .thinking: return 4_096
        case .expert: return 8_192
        case .ultra: return 16_384
        }
    }
}

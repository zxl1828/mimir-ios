import Foundation

/// 思考程度：关闭 / Low / Medium / High / Max 五档。
///
/// 档位同时驱动「思考强度」分段控件的视觉表现与发送请求时的模型参数；
/// 「关闭」表示不使用深度思考参数（最低 token 预算），并非跳过请求。
enum ThinkingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case light
    case thinking
    case expert
    case ultra

    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "off", "none", "disabled":
            self = .off
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
        if raw == "off" || raw == "none" {
            self = .off
        } else if raw == "quick" || raw == "light" {
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
        case .off: return "Off"
        case .light: return "Low"
        case .thinking: return "Medium"
        case .expert: return "High"
        case .ultra: return "Max"
        }
    }

    /// 浮动卡片大标题与状态胶囊后缀（与实机参考图 Ultra 对齐）。
    var heroTitle: String {
        switch self {
        case .off: return "关闭"
        case .light: return "Low"
        case .thinking: return "Medium"
        case .expert: return "High"
        case .ultra: return "Max"
        }
    }

    /// 分段控件里用的短标签，单行显示，绝不出现「Ultr / a」折行。
    var segmentLabel: String {
        switch self {
        case .off: return "关闭"
        case .light: return "Low"
        case .thinking: return "Medium"
        case .expert: return "High"
        case .ultra: return "Max"
        }
    }

    // MARK: - 模型参数映射

    var temperature: Double {
        switch self {
        case .off: return 0.75
        case .light: return 0.70
        case .thinking: return 0.60
        case .expert: return 0.45
        case .ultra: return 0.30
        }
    }

    var maxTokens: Int {
        switch self {
        case .off: return 1_536
        case .light: return 2_048
        case .thinking: return 4_096
        case .expert: return 8_192
        case .ultra: return 16_384
        }
    }
}

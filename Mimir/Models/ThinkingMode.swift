import SwiftUI

/// 思考程度。左 → 右：Light / High / Extra High / Max（与电脑端一致的四档力度）。
///
/// 档位同时驱动两件事：滑块的视觉表现，以及发送请求时的模型参数。
enum ThinkingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case quick
    case thinking
    case expert
    case ultra

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Light"
        case .thinking: return "High"
        case .expert: return "X-High"
        case .ultra: return "Max"
        }
    }

    // MARK: - 模型参数映射

    var temperature: Double {
        switch self {
        case .quick: return 0.75
        case .thinking: return 0.60
        case .expert: return 0.45
        case .ultra: return 0.30
        }
    }

    var maxTokens: Int {
        switch self {
        case .quick: return 2_048
        case .thinking: return 4_096
        case .expert: return 8_192
        case .ultra: return 16_384
        }
    }

}

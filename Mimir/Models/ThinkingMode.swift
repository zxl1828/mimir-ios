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

    /// 胶囊里的短标签，避免「Extra High」把按钮撑太宽。
    var shortTitle: String {
        title
    }

    var subtitle: String {
        switch self {
        case .quick: return "几乎不思考，速度优先"
        case .thinking: return "常规推理，日常够用"
        case .expert: return "更深推理，复杂问题"
        case .ultra: return "全力推理，长链条任务"
        }
    }

    var systemImage: String {
        switch self {
        case .quick: return "bolt.fill"
        case .thinking: return "brain"
        case .expert: return "graduationcap.fill"
        case .ultra: return "sparkles"
        }
    }

    var tint: Color { AppColor.thinkingTint(for: self) }

    /// 0...1 归一化位置，用于滑块几何计算。
    var normalized: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0) / Double(max(Self.allCases.count - 1, 1))
    }

    /// 由滑块位置解析出最近档位（拖动过程中实时使用）。
    static func nearest(progress: Double) -> ThinkingMode {
        let clamped = min(max(progress, 0), 1)
        let scaled = clamped * Double(allCases.count - 1)
        let index = Int(scaled.rounded())
        return allCases[min(max(index, 0), allCases.count - 1)]
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

    /// 是否要求模型输出思考过程（用于渲染折叠的思考区）。
    var exposesReasoning: Bool {
        switch self {
        case .quick: return false
        case .thinking, .expert, .ultra: return true
        }
    }

    /// 是否启用预热动画（Ultra 的持续动效）。
    var isEmbellished: Bool { self == .ultra }
}

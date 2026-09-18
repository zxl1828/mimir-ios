import SwiftUI
import UIKit

/// 动画常量集中管理，取值来自设计规格。
enum AppAnimation {

    /// 侧边栏抽屉开合。
    static var sidebar: Animation { .spring(response: 0.35, dampingFraction: 0.8) }
    /// 技能选择浮层。
    static var skillPicker: Animation { .spring(response: 0.3, dampingFraction: 0.75) }
    /// 思考档位吸附。
    static var thinkingSnap: Animation { .spring(response: 0.3, dampingFraction: 0.75) }
    /// 引导页浮入。
    static var onboarding: Animation { .spring(response: 0.5, dampingFraction: 0.8) }
    /// 胶囊 / 标签切换。
    static var chip: Animation { .spring(response: 0.35, dampingFraction: 0.85) }
    /// 消息气泡出现。
    static var bubble: Animation { .spring(response: 0.4, dampingFraction: 0.9) }
    /// 推荐胶囊淡入。
    static var recommend: Animation { .easeOut(duration: 0.22) }
    /// 光晕扩散。
    static var glow: Animation { .easeOut(duration: 0.6) }
    /// Ultra 呼吸脉冲。
    static var ultraBreath: Animation { .easeInOut(duration: 1.6).repeatForever(autoreverses: true) }
    /// Ultra 流光循环。
    static var ultraFlow: Animation { .linear(duration: 2.4).repeatForever(autoreverses: false) }
    /// 语音球脉冲。
    static var orbPulse: Animation { .easeInOut(duration: 0.28) }
    static var orbSlowSpin: Animation { .linear(duration: 3.2).repeatForever(autoreverses: false) }
}

/// 触觉反馈统一出口，便于在真机上集中调校。
@MainActor
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selectionChanged() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

import SwiftUI
import UIKit

/// 语音球：屏幕中央的 3D 超流体液态玻璃球体，形状与光效随会话状态与音频能量变化。
/// 委托给 ADA 级的 `LiquidOrbVisualizer` 渲染。
struct VoiceOrb: View {

    let state: VoiceSessionState
    var inputLevel: Double = 0
    var outputLevel: Double = 0
    var diameter: CGFloat = 190

    var body: some View {
        LiquidOrbVisualizer(
            mode: .duplexSphere,
            inputLevel: inputLevel,
            outputLevel: outputLevel,
            isSpeaking: state == .speaking,
            diameter: diameter
        )
    }
}

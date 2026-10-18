import SwiftUI
import UIKit

/// 双层悬浮控制底座与分贝计（FloatingAudioDock）。
///
/// 严格复刻参考图 1 与参考图 2 的双层悬浮跑道型底座与精密声级分贝标尺：
/// - **双层悬浮底座**：高透光悬浮玻璃跑道型胶囊（.ultraThinMaterial），外覆 0.8pt 焦散高光描边；
/// - **动态声波主按钮**：中央 68x68pt 鸢尾紫（#7D52F4）渐变实体发光圆，正中心为声波动态符号，
///   在收音/发声态向外爆发扩散多重同心声波扩散环（Concentric Pulse Shockwaves）；
/// - **两侧辅助功能键**：左侧切换麦克风静音，右侧切换字幕卡片排版；
/// - **精密分贝刻度量规**：内嵌精密声级指示标尺（-36 dB / -42 dB 至 0 dB），
///   随当前音频电平从左向右实时填充发光紫色点阵。
public struct FloatingAudioDock: View {

    public enum DockStyle: Sendable {
        case liveDuplex
        case transcription
    }

    public var style: DockStyle = .liveDuplex
    public var isMuted: Bool = false
    public var isSpeakingOrGenerating: Bool = false
    public var audioLevel: Double = 0.0 // 归一化音频能量 0.0 ~ 1.0

    public var onLeftButtonTapped: (() -> Void)?
    public var onCenterButtonTapped: (() -> Void)?
    public var onRightButtonTapped: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    // 核心色彩令牌
    private let irisViolet = Color(hex: "7D52F4")
    private let electricViolet = Color(hex: "9B70FF")

    public init(
        style: DockStyle = .liveDuplex,
        isMuted: Bool = false,
        isSpeakingOrGenerating: Bool = false,
        audioLevel: Double = 0.0,
        onLeftButtonTapped: (() -> Void)? = nil,
        onCenterButtonTapped: (() -> Void)? = nil,
        onRightButtonTapped: (() -> Void)? = nil
    ) {
        self.style = style
        self.isMuted = isMuted
        self.isSpeakingOrGenerating = isSpeakingOrGenerating
        self.audioLevel = audioLevel
        self.onLeftButtonTapped = onLeftButtonTapped
        self.onCenterButtonTapped = onCenterButtonTapped
        self.onRightButtonTapped = onRightButtonTapped
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 双层跑道型悬浮控制底座
            dualLayerGlassDock

            // 精密分贝刻度量规 (-36 dB ~ 0 dB)
            precisionDecibelGauge
                .padding(.horizontal, 22)
                .padding(.top, 2)
        }
    }

    // MARK: - 1. 双层悬浮控制底盘 (Dual-Layer Floating Capsule)

    private var dualLayerGlassDock: some View {
        ZStack {
            // 外层跑道型悬浮高透光毛玻璃胶囊
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(colorScheme == .dark ? Color(hex: "21182F").opacity(0.96) : Color.white.opacity(0.88))
                .liquidGlass(.regular, in: .rect(cornerRadius: 44))
                .overlay {
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.24 : 0.40), location: 0.0),
                                    .init(color: irisViolet.opacity(0.42), location: 0.50),
                                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: irisViolet.opacity(0.22), radius: 26, x: 0, y: 10)

            // 三颗控制按键水平阵列
            HStack(spacing: 28) {
                // 左侧麦克风静音控制
                leftAuxiliaryButton

                // 中央核心声波主按钮（含同心声波扩散环）
                centerActionButton

                // 右侧字幕卡片排版切换
                rightAuxiliaryButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(height: 88)
        .padding(.horizontal, 16)
    }

    // MARK: - 2. 左侧辅助键

    private var leftAuxiliaryButton: some View {
        Button {
            triggerHaptic(.medium)
            onLeftButtonTapped?()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        colorScheme == .dark ? Color(hex: "342749") : Color(hex: "F2EDFA")
                    )
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.20 : 0.35), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }

                Image(systemName: leftButtonIcon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isMuted ? Color(hex: "D94D68") : irisViolet)
            }
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(isMuted ? "取消静音" : "静音")
    }

    private var leftButtonIcon: String {
        return isMuted ? "mic.slash.fill" : "mic.fill"
    }

    // MARK: - 3. 中央核心动态声波主按钮 (Center Action Orb)

    private var centerActionButton: some View {
        Button {
            triggerHaptic(.heavy)
            onCenterButtonTapped?()
        } label: {
            ZStack {
                // 实体渐变发光主圆 (68x68)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "956BFF"),
                                irisViolet,
                                Color(hex: "683CE6")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.1)
                    }
                    .shadow(color: irisViolet.opacity(0.85), radius: 18, x: 0, y: 4)

                // 按钮核心动态图标
                centerButtonIconView
            }
            .frame(width: 66, height: 66)
            .overlay { concentricPulseRings.allowsHitTesting(false) }
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(centerAccessibilityLabel)
    }

    // 同心扩散波纹环
    private var concentricPulseRings: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let active = audioLevel > 0.04 || isSpeakingOrGenerating

            ZStack {
                ForEach(0..<3, id: \.self) { idx in
                    let delay = Double(idx) * 0.32
                    let progress = (time * 0.9 + delay).truncatingRemainder(dividingBy: 1.0)
                    let scale = 0.95 + progress * 0.65
                    let alpha = (1.0 - progress) * (active ? (0.45 + audioLevel * 0.40) : 0.18)

                    Circle()
                        .stroke(
                            irisViolet.opacity(alpha),
                            lineWidth: max(0.8, (1.0 - progress) * 2.5)
                        )
                        .frame(width: 72 * scale, height: 72 * scale)
                }
            }
        }
    }

    @ViewBuilder
    private var centerButtonIconView: some View {
        if isSpeakingOrGenerating {
            // 停止打断回答方块
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white)
                .frame(width: 20, height: 20)
        } else {
            // 高保真 5 柱动态跳动声波；布局固定，音频流只改变柱高。
            TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3.5) {
                    ForEach(0..<5, id: \.self) { barIdx in
                        let seed = Double(barIdx) * 0.85
                        let wave = (sin(time * 6.0 + seed) * 0.5 + 0.5)
                        let heightFactor = 0.35 + (audioLevel * 0.65) * wave + (audioLevel > 0.05 ? 0.25 : 0.0)
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .frame(width: 3.2, height: 24)
                            .scaleEffect(y: heightFactor, anchor: .center)
                    }
                }
                .frame(width: 32, height: 30)
            }
        }
    }

    private var centerAccessibilityLabel: String {
        if isSpeakingOrGenerating { return "停止回答" }
        return "开始或暂停聆听"
    }

    // MARK: - 4. 右侧字幕排版切换

    private var rightAuxiliaryButton: some View {
        Button {
            triggerHaptic(.light)
            onRightButtonTapped?()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        colorScheme == .dark ? Color(hex: "342749") : Color(hex: "F2EDFA")
                    )
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.20 : 0.35), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }

                Image(systemName: rightButtonIcon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "85DDE0") : Color(hex: "268E9E"))
            }
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(style == .liveDuplex ? "切换到转写卡片" : "切换到全双工显示")
    }

    private var rightButtonIcon: String {
        return style == .liveDuplex ? "captions.bubble" : "waveform"
    }

    // MARK: - 5. 精密分贝刻度量规 (Bottom Decibel Gauge: -36 dB ~ 0 dB)

    private var precisionDecibelGauge: some View {
        HStack(spacing: 10) {
            // 左端标注
            Text(style == .transcription ? "-42 dB" : "-36 dB")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? Color(hex: "C5B8D8") : Color(hex: "746A80"))

            // 中间点阵音量电平驱动发光紫色点阵实时填充
            GeometryReader { proxy in
                let totalDots = 30
                let activeDots = Int(min(max(audioLevel, 0.0), 1.0) * Double(totalDots))

                HStack(spacing: (proxy.size.width - CGFloat(totalDots) * 3.0) / CGFloat(totalDots - 1)) {
                    ForEach(0..<totalDots, id: \.self) { idx in
                        let isActive = idx <= activeDots && audioLevel > 0.02
                        let isPeak = idx == activeDots && activeDots > 0

                        Circle()
                            .fill(
                                isActive
                                    ? (isPeak ? Color.white : electricViolet)
                                    : (colorScheme == .dark ? Color(hex: "514361") : Color(hex: "DCD5E7"))
                            )
                            .frame(width: 3.5, height: 3.5)
                            .scaleEffect(isPeak ? 1.12 : 1.0)
                            .shadow(color: isActive ? electricViolet.opacity(0.85) : Color.clear, radius: isPeak ? 4 : 2)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            // 右端标注
            Text("0 dB")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? Color(hex: "C5B8D8") : Color(hex: "746A80"))
        }
    }

    // MARK: - 触觉反馈辅助

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

import SwiftUI
import SwiftData
import AVFoundation
import UIKit

/// 次世代全双工实时语音交互视窗（VoiceDuplexView）。
///
/// 斩获 Apple Design Award（视觉与图像类）标准的次世代超流体玻璃全双工实时语音交互视窗：
/// - **深色全双工形态（核心交互态，参考图 1）**：
///   顶部外设胶囊（AirPods Pro + 降噪模式 + 动态波形跳动）与引擎状态浮条（Mimir Neural Core · 110ms · Spatial Audio 48kHz）；
///   中央 3D 虹彩超流体玻璃悬浮球（Liquid Glass Orb）外覆液态金属环与多重星轨发光粒子；
///   双通道流式打字转写卡片（LiveTranscriptSlab）；
///   双层悬浮底座（FloatingAudioDock）与 -36 dB 精密分贝指示标尺。
/// - **浅色转写形态（参考图 2）**：
///   中央 3D 梦幻流体动态声波丝带（Iridescent Wave Ribbon）与音频时间轴量规；
///   双层时间戳沉浸式转写卡片与分贝刻度。
public struct VoiceDuplexView: View {

    public let chat: ChatViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: VoiceSessionViewModel?
    @State private var isMuted: Bool = false
    @State private var visualMode: LiquidOrbVisualizer.VisualMode = .duplexSphere
    @State private var showMinutes: Bool = false
    @State private var minutesText: String?
    @State private var isSummarizing: Bool = false
    @State private var showTonePicker: Bool = false

    // 核心品牌色
    private let irisViolet = Color(hex: "7D52F4")
    private let electricViolet = Color(hex: "9B70FF")
    private let deepPlumNight = Color(hex: "0D061A")

    public init(chat: ChatViewModel) {
        self.chat = chat
    }

    public var body: some View {
        ZStack {
            // ① 深度环境渐变与紫雾焦散背景
            duplexAmbientBackground

            // ② 主舞台视窗
            if let session {
                duplexMainStage(session)
            } else {
                loadingStage
            }
        }
        .preferredColorScheme(visualMode == .duplexSphere ? .dark : nil)
        .task {
            if session == nil {
                session = VoiceSessionViewModel(settings: settings, modelContext: modelContext)
            }
            await session?.start(conversation: chat.conversation)
        }
        .onDisappear {
            session?.end()
        }
        .sheet(isPresented: $showTonePicker) {
            VoiceTonePickerView()
        }
        .sheet(isPresented: $showMinutes) {
            VoiceMinutesView(text: minutesText ?? "", onDismiss: { showMinutes = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 背景与环境氛围

    private var duplexAmbientBackground: some View {
        ZStack {
            if visualMode == .duplexSphere {
                // 深色形态：沉浸紫夜星空底板
                LinearGradient(
                    colors: [
                        Color(hex: "0B0516"),
                        Color(hex: "20103B"),
                        Color(hex: "0D061A")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 灵动岛下方与中央球体背后的环境紫雾漫射
                RadialGradient(
                    colors: [
                        irisViolet.opacity(0.38),
                        electricViolet.opacity(0.18),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.32),
                    startRadius: 40,
                    endRadius: 400
                )
                .blur(radius: 24)
            } else {
                // 浅色形态：珍珠透光粉紫极光漫射
                LinearGradient(
                    colors: [
                        Color(hex: "F8F5FF"),
                        Color(hex: "EFE7FC"),
                        Color(hex: "FDFBFF")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        irisViolet.opacity(0.15),
                        Color(hex: "70E1FD").opacity(0.10),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.35),
                    startRadius: 30,
                    endRadius: 320
                )
            }
        }
        .ignoresSafeArea()
    }

    private var loadingStage: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(irisViolet)
                .scaleEffect(1.2)
            Text("正在链接神经语音通道…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 主舞台纵向布局

    private func duplexMainStage(_ session: VoiceSessionViewModel) -> some View {
        VStack(spacing: 0) {
            // 1. 顶部控制栏与外设状态胶囊
            duplexHeaderBar(session)

            // 2. 神经引擎与低延迟空间音频状态浮条
            neuralEngineStatusBar
                .padding(.top, 10)

            Spacer(minLength: 4)

            // 3. 中央核心视觉锚点：3D 超流体声波共振球 / 流体丝带
            LiquidOrbVisualizer(
                mode: visualMode,
                inputLevel: isMuted ? 0.0 : session.inputLevel,
                outputLevel: session.outputLevel,
                isSpeaking: session.state == .speaking,
                diameter: 195
            )
            .padding(.vertical, 4)

            Spacer(minLength: 6)

            // 4. 实时转写与推理上下文悬浮卡片 (LiveTranscriptSlab)
            LiveTranscriptSlab(
                displayMode: visualMode == .duplexSphere ? .liveDuplex : .transcriptionCards,
                userQuery: latestUserText(session),
                aiResponse: latestAIText(session),
                statusHint: currentStatusHint(session),
                onMinutesTapped: { generateMinutes(session) }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // 5. 双层悬浮控制底座与分贝计 (FloatingAudioDock)
            FloatingAudioDock(
                style: visualMode == .duplexSphere ? .liveDuplex : .transcription,
                isMuted: isMuted,
                isSpeakingOrGenerating: session.state == .speaking || session.state == .thinking,
                audioLevel: isMuted ? 0.0 : max(session.inputLevel, session.outputLevel),
                onLeftButtonTapped: {
                    toggleMute(session)
                },
                onCenterButtonTapped: {
                    handleCenterOrbAction(session)
                },
                onRightButtonTapped: {
                    toggleVisualMode()
                }
            )
            .padding(.bottom, 10)
        }
    }

    // MARK: - 1. 顶部状态栏与外设胶囊 (Header & Peripherals)

    private func duplexHeaderBar(_ session: VoiceSessionViewModel) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 左侧操作区：悬浮圆形极细边框高透光纯白玻璃关闭按钮
            Button {
                Haptics.impact(.light)
                session.end()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    }
                    .liquidGlass(.regular, in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                    }
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("退出全双工语音")

            Spacer()

            // 中央品牌标识：Mimir + LIVE DUPLEX
            VStack(spacing: 2) {
                Text("Mimir")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("LIVE DUPLEX")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .offset(x: 6) // 微调居中光学平衡

            Spacer()

            // 右侧外设实时胶囊 (AirPods Pro + 降噪模式 + 迷你跳动波形)
            airPodsPeripheralPill
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // AirPods Pro 状态外设胶囊
    private var airPodsPeripheralPill: some View {
        Button {
            Haptics.impact(.light)
            showTonePicker = true
        } label: {
            HStack(spacing: 7) {
                // AirPods 紧凑图标
                Image(systemName: "airpodspro")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AirPods Pro")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("Noise Cancelling")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.60))
                }

                // 动态微型声波动画（3~4 条紫色迷你波形柱根据当前声音实时跳动）
                miniAudioWaveformBars
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(hex: "1F1235").opacity(0.58))
            }
            .liquidGlass(.regular, in: .capsule)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
            }
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel("外设音频与音色设置")
    }

    // 迷你声波跳动条 (3-4 柱)
    private var miniAudioWaveformBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let active = (session?.inputLevel ?? 0) > 0.05 || (session?.outputLevel ?? 0) > 0.05

            HStack(spacing: 2.2) {
                ForEach(0..<4, id: \.self) { idx in
                    let seed = Double(idx) * 1.1
                    let wave = sin(time * 8.0 + seed) * 0.5 + 0.5
                    let barH = active ? (4.0 + wave * 9.0) : 3.0

                    Capsule(style: .continuous)
                        .fill(electricViolet)
                        .frame(width: 2.2, height: barH)
                }
            }
            .frame(width: 14, height: 16)
        }
    }

    // MARK: - 2. 神经引擎与空间音频状态浮条

    private var neuralEngineStatusBar: some View {
        HStack(spacing: 8) {
            // 实时神经核心状态指示灯（呼吸发光绿点）
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "34C759"))
                    .frame(width: 6, height: 6)
                    .shadow(color: Color(hex: "34C759").opacity(0.85), radius: 4)

                Text("Mimir Neural Core · 110ms")
            }

            // 分割坚线
            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(width: 1, height: 10)

            // 空间音频规格
            Text("Spatial Audio 48kHz")
        }
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.80))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color(hex: "1F1235").opacity(0.45))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
        }
    }

    // MARK: - 交互事件处理

    private func toggleMute(_ session: VoiceSessionViewModel) {
        isMuted.toggle()
        if isMuted {
            // 静音态
            session.stopAll()
        } else {
            // 恢复采集
            Task {
                await session.start(conversation: chat.conversation)
            }
        }
    }

    private func handleCenterOrbAction(_ session: VoiceSessionViewModel) {
        if session.state == .speaking || session.state == .thinking {
            // 打断当前回答
            session.interrupt()
        } else {
            // 重新开启或切换聆听
            session.toggleListening()
        }
    }

    private func toggleVisualMode() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
            visualMode = (visualMode == .duplexSphere) ? .transcriptRibbon : .duplexSphere
        }
    }

    private func generateMinutes(_ session: VoiceSessionViewModel) {
        guard !isSummarizing else { return }
        isSummarizing = true
        Task {
            let succeeded = await session.generateMinutes()
            if succeeded {
                minutesText = session.lines.last(where: { !$0.isUser })?.text ?? ""
                showMinutes = true
            }
            isSummarizing = false
        }
    }

    // MARK: - 文本解析辅助

    private func latestUserText(_ session: VoiceSessionViewModel) -> String? {
        if !session.partialText.isEmpty {
            return session.partialText
        }
        return session.lines.last(where: { $0.isUser })?.text
    }

    private func latestAIText(_ session: VoiceSessionViewModel) -> String? {
        if session.state == .thinking {
            return "Synthesizing contextual thoughts..."
        }
        return session.lines.last(where: { !$0.isUser })?.text
    }

    private func currentStatusHint(_ session: VoiceSessionViewModel) -> String {
        switch session.state {
        case .listening:
            return "Listening actively · Tap mic or speak freely"
        case .transcribing:
            return "Transcribing voice stream…"
        case .thinking:
            return "Multi-agent reasoning in progress…"
        case .speaking:
            return "Speaking · Tap orb or speak to interrupt"
        case .interrupted:
            return "Interrupted · Ready for next turn"
        case .idle:
            return "Standby · Tap center orb to speak"
        case .unavailable:
            return session.infoText ?? "Voice route unavailable"
        }
    }
}

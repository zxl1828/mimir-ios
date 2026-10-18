import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import UIKit

/// 次世代全双工实时语音交互视窗（VoiceDuplexView）。
///
/// 全双工实时语音交互视窗，使用同一套音频响应波形和稳定的双向字幕布局。
struct VoiceDuplexView: View {

    private enum SheetRoute: String, Identifiable {
        case tonePicker
        case minutes
        var id: String { rawValue }
    }

    let chat: ChatViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var session: VoiceSessionViewModel?
    @State private var transcriptDisplayMode: LiveTranscriptSlab.DisplayMode = .liveDuplex
    @State private var minutesText = ""
    @State private var minutesError: String?
    @State private var isSummarizing: Bool = false
    @State private var activeSheet: SheetRoute?

    // 核心品牌色
    private let irisViolet = Color(hex: "7D52F4")

    init(chat: ChatViewModel) {
        self.chat = chat
    }

    var body: some View {
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
        .task {
            if session == nil {
                session = VoiceSessionViewModel(settings: settings, modelContext: modelContext)
            }
            await session?.start(conversation: chat.conversation)
        }
        .onDisappear {
            session?.end()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            session?.enterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            session?.enterForeground()
        }
        .sheet(item: $activeSheet) { route in
            switch route {
            case .tonePicker:
                VoiceTonePickerView()
            case .minutes:
                VoiceMinutesView(
                    text: minutesText,
                    isLoading: isSummarizing,
                    errorMessage: minutesError,
                    onRetry: { if let session { generateMinutes(session) } },
                    onDismiss: { activeSheet = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 背景与环境氛围

    private var duplexAmbientBackground: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(hex: "120D1D"), Color(hex: "1B1230"), Color(hex: "120D1D")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [Color.white, Color(hex: "F8F6FD"), Color(hex: "F2EBFC")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            RadialGradient(
                colors: [
                    irisViolet.opacity(colorScheme == .dark ? 0.24 : 0.14),
                    Color(hex: "70E1FD").opacity(colorScheme == .dark ? 0.10 : 0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 30,
                endRadius: 320
            )
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
        GeometryReader { geometry in
        let veryCompact = geometry.size.height < 560
        let compact = geometry.size.height < 720
        let waveDiameter: CGFloat = veryCompact ? 116 : (compact ? 142 : 184)
        let waveHeight: CGFloat = veryCompact ? 104 : (compact ? 136 : 178)
        let isMuted = session.isMicrophoneMuted
        VStack(spacing: 0) {
            // 1. 顶部控制栏与外设状态胶囊
            duplexHeaderBar(session)

            // 2. 语音链路状态浮条
            neuralEngineStatusBar(session)
                .padding(.top, 8)

            Spacer(minLength: compact ? 2 : 6)

            // 3. 中央核心视觉锚点：实时流体声波
            VoiceWaveformVisualizer(
                inputLevel: isMuted ? 0.0 : session.inputLevel,
                outputLevel: session.outputLevel,
                isSpeaking: session.state == .speaking,
                diameter: waveDiameter
            )
            .frame(maxWidth: .infinity)
            .frame(height: waveHeight)

            Spacer(minLength: compact ? 3 : 8)

            // 4. 实时转写与推理上下文悬浮卡片 (LiveTranscriptSlab)
            LiveTranscriptSlab(
                displayMode: transcriptDisplayMode,
                userQuery: latestUserText(session),
                aiResponse: latestAIText(session),
                statusHint: currentStatusHint(session),
                isCompact: compact,
                onMinutesTapped: { generateMinutes(session) }
            )
            .padding(.horizontal, 16)
            .frame(height: compact ? 160 : 194, alignment: .top)

            // 5. 双层悬浮控制底座与分贝计 (FloatingAudioDock)
            FloatingAudioDock(
                style: transcriptDisplayMode == .liveDuplex ? .liveDuplex : .transcription,
                isMuted: isMuted,
                isSpeakingOrGenerating: session.state == .speaking || session.state == .thinking,
                audioLevel: isMuted ? 0.0 : max(session.inputLevel, session.outputLevel),
                onLeftButtonTapped: {
                    session.setMicrophoneMuted(!session.isMicrophoneMuted)
                },
                onCenterButtonTapped: {
                    handleCenterAction(session)
                },
                onRightButtonTapped: {
                    toggleTranscriptDisplayMode()
                }
            )
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "F4EFFB") : Color(hex: "3D3150"))
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(colorScheme == .dark ? Color(hex: "2B203B").opacity(0.94) : Color.white.opacity(0.76))
                    }
                    .liquidGlass(.regular, in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.30 : 0.86), lineWidth: 0.8)
                    }
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("退出全双工语音")

            Spacer(minLength: 0)
            audioOutputControl
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .overlay {
            VStack(spacing: 2) {
                Text("Mimir")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "F2ECFA") : Color(hex: "34264A"))
                Text("LIVE DUPLEX")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "C5B8D8") : Color(hex: "796E87"))
            }
            .allowsHitTesting(false)
        }
    }

    private var audioOutputControl: some View {
        HStack(spacing: 6) {
            AudioRoutePickerView()
                .frame(width: 38, height: 38)
                .background(colorScheme == .dark ? Color(hex: "2B203B").opacity(0.94) : Color.white.opacity(0.82), in: Circle())
                .liquidGlass(.regular, in: .circle)
                .overlay { Circle().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.30 : 0.9), lineWidth: 0.8).allowsHitTesting(false) }
                .accessibilityLabel("选择蓝牙或 AirPlay 音频输出")

            Button {
                Haptics.impact(.light)
                activeSheet = .tonePicker
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "C6B5FF") : irisViolet)
                    .frame(width: 38, height: 38)
                    .background(colorScheme == .dark ? Color(hex: "2B203B").opacity(0.94) : Color.white.opacity(0.82), in: Circle())
                    .liquidGlass(.regular, in: .circle)
                    .overlay { Circle().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.30 : 0.9), lineWidth: 0.8).allowsHitTesting(false) }
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("选择语音音色")
        }
    }

    // MARK: - 2. 神经引擎与空间音频状态浮条

    private func neuralEngineStatusBar(_ session: VoiceSessionViewModel) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(session.isActive ? Color(hex: "34C759") : Color(hex: "A99EB6"))
                    .frame(width: 6, height: 6)
                Text("语音链路 · \(session.state.title)")
            }
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(colorScheme == .dark ? Color(hex: "D6CCE5") : Color(hex: "514660"))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? Color(hex: "21182F").opacity(0.92) : Color.white.opacity(0.68))
        }
        .overlay {
            Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.88), lineWidth: 0.7)
        }
    }

    // MARK: - 交互事件处理

    private func handleCenterAction(_ session: VoiceSessionViewModel) {
        if session.state == .speaking || session.state == .thinking {
            // 打断当前回答
            session.interrupt()
        } else {
            // 重新开启或切换聆听
            session.toggleListening()
        }
    }

    private func toggleTranscriptDisplayMode() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
            transcriptDisplayMode = transcriptDisplayMode == .liveDuplex ? .transcriptionCards : .liveDuplex
        }
    }

    private func generateMinutes(_ session: VoiceSessionViewModel) {
        guard !isSummarizing else { return }
        minutesText = ""
        minutesError = nil
        isSummarizing = true
        activeSheet = .minutes
        Task {
            let succeeded = await session.generateMinutes()
            if succeeded {
                minutesText = session.lines.last(where: { !$0.isUser })?.text ?? ""
            } else {
                minutesError = session.infoText ?? "纪要生成失败，请检查连接后重试。"
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
            return "Mimir 正在组织回复…"
        }
        return session.lines.last(where: { !$0.isUser })?.text
    }

    private func currentStatusHint(_ session: VoiceSessionViewModel) -> String {
        if session.isMicrophoneMuted { return "麦克风已静音" }
        switch session.state {
        case .listening:
            return "正在聆听 · 开口即可继续"
        case .transcribing:
            return "正在转写语音…"
        case .thinking:
            return "Mimir 正在思考…"
        case .speaking:
            return "正在回答 · 轻点主键可打断"
        case .interrupted:
            return "已打断 · 可以继续说话"
        case .idle:
            return "待命 · 轻点主键开始聆听"
        case .unavailable:
            return session.infoText ?? "语音通道暂不可用"
        }
    }
}

private struct AudioRoutePickerView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        updateAppearance(picker)
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        updateAppearance(picker)
    }

    private func updateAppearance(_ picker: AVRoutePickerView) {
        if colorScheme == .dark {
            picker.tintColor = UIColor(red: 0.83, green: 0.78, blue: 0.93, alpha: 1)
        } else {
            picker.tintColor = UIColor(red: 0.36, green: 0.28, blue: 0.52, alpha: 1)
        }
        picker.activeTintColor = UIColor(red: 0.49, green: 0.32, blue: 0.96, alpha: 1)
    }
}

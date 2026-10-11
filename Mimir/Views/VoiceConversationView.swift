import SwiftUI
import SwiftData
import UIKit

/// Full-screen duplex voice conversation surface.
/// The session model owns permissions, routing, VAD, streaming and TTS.
struct VoiceConversationView: View {
    let chat: ChatViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var session: VoiceSessionViewModel?
    @State private var isSummarizing = false
    @State private var minutesText: String?
    @State private var showMinutes = false
    @State private var showTonePicker = false

    var body: some View {
        ZStack {
            voiceBackground
            if let session { voiceStage(session) }
            else { ProgressView().tint(AppColor.brandIndigo) }
        }
        .preferredColorScheme(.dark)
        .task {
            if session == nil { session = VoiceSessionViewModel(settings: settings, modelContext: modelContext) }
            await session?.start(conversation: chat.conversation)
        }
        .onDisappear { session?.end() }
        .sheet(isPresented: $showTonePicker) { VoiceTonePickerView() }
        .sheet(isPresented: $showMinutes) {
            VoiceMinutesView(text: minutesText ?? "", onDismiss: { showMinutes = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var voiceBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0F0A1B"), Color(hex: "21143B"), Color(hex: "100A1B")], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [AppColor.brandPurple.opacity(0.42), .clear], center: .center, startRadius: 30, endRadius: 360).blur(radius: 8)
        }.ignoresSafeArea()
    }

    private func voiceStage(_ session: VoiceSessionViewModel) -> some View {
        VStack(spacing: 0) {
            header(session)
            neuralStatus
            Spacer(minLength: 8)
            ZStack {
                VoiceOrb(state: session.state, inputLevel: session.inputLevel, outputLevel: session.outputLevel, diameter: 188)
                    .frame(maxWidth: .infinity)
                orbitDust
            }.frame(maxWidth: .infinity)
            transcriptCard(session).padding(.top, 4)
            Spacer(minLength: 12)
            controlIsland(session)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private func header(_ session: VoiceSessionViewModel) -> some View {
        HStack(spacing: 10) {
            Button { session.end(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .liquidGlass(.regular, in: .circle)
            .accessibilityLabel("退出语音对话")
            Spacer()
            VStack(spacing: 1) {
                Text("Mimir").font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(.white)
                Text("LIVE DUPLEX").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
            Button { showTonePicker = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "airpodspro")
                    Text("AirPods").font(.system(size: 10, weight: .semibold))
                }.padding(.horizontal, 10).frame(height: 38)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .liquidGlass(.regular, in: .capsule)
            .accessibilityLabel("音频设备与音色")
        }
        .foregroundStyle(.white)
    }

    private var neuralStatus: some View {
        HStack(spacing: 8) {
            Circle().fill(AppColor.success).frame(width: 7, height: 7).shadow(color: AppColor.success, radius: 6)
            Text("Mimir Neural Core · 110ms")
            Capsule().fill(.white.opacity(0.28)).frame(width: 1, height: 13)
            Text("Spatial Audio 48kHz")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .liquidGlass(.regular, in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.8) }
        .padding(.top, 12)
    }

    private var orbitDust: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<24 {
                    let seed = Double(index) * 0.71
                    let angle = time * (0.22 + seed * 0.01) + seed
                    let radius = 120 + sin(time * 0.7 + seed) * 25
                    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * 0.62)
                    let dot = 1.0 + CGFloat(index % 3) * 0.6
                    context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(AppColor.brandPurple.opacity(0.22 + Double(index % 4) * 0.08)))
                }
            }
        }
        .frame(width: 320, height: 270)
        .allowsHitTesting(false)
    }

    private func transcriptCard(_ session: VoiceSessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                Text(session.lines.last(where: { $0.isUser })?.text ?? "Tap the mic or speak freely")
                    .font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.70)).lineLimit(3)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColor.brandPurple.opacity(0.9))
            }
            Text(session.lines.last(where: { !$0.isUser })?.text ?? statusText(session))
                .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(AppColor.brandPurple.opacity(0.98)).lineLimit(4).contentTransition(.opacity)
            if !session.partialText.isEmpty {
                Text(session.partialText).font(.system(size: 15, design: .rounded)).foregroundStyle(.white.opacity(0.66)).lineLimit(2)
            }
            HStack {
                Text("Listening actively · Tap mic or speak freely").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.48))
                Spacer()
                Button { generateMinutes(from: session) } label: {
                    Label(isSummarizing ? "整理中" : "会议纪要", systemImage: "text.badge.checkmark").font(.system(size: 10, weight: .semibold))
                }.buttonStyle(.plain).foregroundStyle(AppColor.brandPurple).disabled(isSummarizing)
            }
        }
        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.regular.tint(AppColor.brandPurple.opacity(0.10)), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 0.9) }
        .shadow(color: AppColor.brandPurple.opacity(0.22), radius: 26, y: 12)
    }

    private func controlIsland(_ session: VoiceSessionViewModel) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 25) {
                Button { session.toggleListening() } label: {
                    Image(systemName: session.state == .listening ? "mic.slash" : "mic.fill").font(.system(size: 18, weight: .semibold)).frame(width: 54, height: 54)
                }.buttonStyle(StaticButtonFeedbackStyle()).liquidGlass(.regular, in: .circle)
                .accessibilityLabel(session.state == .listening ? "静音" : "开始聆听")

                Button {
                    if session.state == .thinking || session.state == .speaking { session.interrupt() } else { session.toggleListening() }
                } label: {
                    Image(systemName: session.state == .thinking || session.state == .speaking ? "stop.fill" : "waveform")
                        .font(.system(size: 23, weight: .bold)).foregroundStyle(.white).frame(width: 78, height: 78)
                        .background(Circle().fill(AppColor.accentGradient)).overlay { Circle().strokeBorder(.white.opacity(0.48), lineWidth: 1) }
                        .shadow(color: AppColor.brandIndigo.opacity(0.70), radius: 22)
                }.buttonStyle(StaticButtonFeedbackStyle())
                .accessibilityLabel(session.state == .thinking || session.state == .speaking ? "停止回答" : "语音主控")

                Button { session.interrupt() } label: {
                    Image(systemName: "hand.raised.fill").font(.system(size: 18, weight: .semibold)).frame(width: 54, height: 54)
                }.buttonStyle(StaticButtonFeedbackStyle()).liquidGlass(.regular, in: .circle)
                .disabled(session.state != .thinking && session.state != .speaking)
                .opacity(session.state == .thinking || session.state == .speaking ? 1 : 0.42)
                .accessibilityLabel("打断回答")
            }
            AudioLevelMeter(level: max(session.inputLevel, session.outputLevel)).frame(height: 12)
        }
        .padding(.horizontal, 18).padding(.vertical, 12).foregroundStyle(.white)
        .liquidGlass(.regular, in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.9) }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }

    private func statusText(_ session: VoiceSessionViewModel) -> String {
        if session.isPreparing { return "Preparing audio route…" }
        if let info = session.infoText, !info.isEmpty { return info }
        return session.state.title
    }

    private func generateMinutes(from session: VoiceSessionViewModel) {
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
}

private struct AudioLevelMeter: View {
    let level: Double
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(0..<28, id: \.self) { index in
                    Capsule().fill(index < Int(level * 28) ? AppColor.brandPurple : .white.opacity(0.16)).frame(height: index.isMultiple(of: 4) ? 8 : 5)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.animation(.easeOut(duration: 0.12), value: level)
    }
}

struct VoiceMinutesView: View {
    let text: String
    let onDismiss: () -> Void
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "text.badge.checkmark").foregroundStyle(AppColor.brandPurple)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("会议纪要").font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("Generated from this voice session").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    Text(text.isEmpty ? "暂无可显示的纪要。" : text)
                        .font(.system(size: 16, design: .rounded)).foregroundStyle(AppColor.primaryText).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .liquidGlass(.regular, in: .rect(cornerRadius: 22)).glassHairline(cornerRadius: 22, opacity: 0.34)
                }.padding(20)
            }
            .navigationTitle("Mimir").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { onDismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: { Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") }
                }
            }
        }
    }
}

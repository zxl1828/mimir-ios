import SwiftUI
import SwiftData
import UIKit

/// Full-screen duplex voice surface. The existing VoiceSessionViewModel owns
/// permissions, Bluetooth routing, VAD, streaming interruption and TTS; this
/// view only presents that state as a focused voice conversation.
struct VoiceConversationView: View {
    let chat: ChatViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var session: VoiceSessionViewModel?

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 1.08)
            if let session {
                conversation(session)
            } else {
                ProgressView().tint(AppColor.brandIndigo)
            }
        }
        .task {
            if session == nil {
                session = VoiceSessionViewModel(settings: settings, modelContext: modelContext)
            }
            await session?.start(conversation: chat.conversation)
        }
        .onDisappear { session?.end() }
    }

    private func conversation(_ session: VoiceSessionViewModel) -> some View {
        VStack(spacing: 0) {
            header(session)
            statusCapsule
            Spacer(minLength: 8)
            VoiceOrb(state: session.state, inputLevel: session.inputLevel, outputLevel: session.outputLevel)
                .frame(maxWidth: .infinity)
            transcript(session)
            Spacer(minLength: 10)
            controls(session)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func header(_ session: VoiceSessionViewModel) -> some View {
        HStack(spacing: 10) {
            Button {
                session.end()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .liquidGlass(.regular, in: .circle)
            .accessibilityLabel("退出语音对话")

            Spacer()
            VStack(spacing: 2) {
                Text("Mimir")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                Text("Neural Core · 110ms")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer()

            Button {
                Haptics.impact(.light)
            } label: {
                Image(systemName: "airpodspro")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .liquidGlass(.regular, in: .circle)
            .accessibilityLabel("音频路由")
        }
        .foregroundStyle(AppColor.primaryText)
    }

    private var statusCapsule: some View {
        HStack(spacing: 7) {
            Circle().fill(AppColor.success).frame(width: 7, height: 7)
            Text("Spatial Audio 48kHz")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(AppColor.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlass(.clear, in: .capsule)
        .glassHairline(cornerRadius: 20, opacity: 0.30)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private func transcript(_ session: VoiceSessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = session.lines.last {
                Text(line.text)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(line.isUser ? AppColor.primaryText : AppColor.brandPurple)
                    .lineLimit(4)
            } else {
                Text(session.isPreparing ? "Preparing audio route…" : "Listening actively · Tap mic or speak freely")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.secondaryText)
            }
            if !session.partialText.isEmpty {
                Text(session.partialText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColor.primaryText.opacity(0.78))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .liquidGlass(.regular, in: .rect(cornerRadius: 22))
        .glassHairline(cornerRadius: 22, opacity: 0.36)
        .padding(.top, 16)
    }

    private func controls(_ session: VoiceSessionViewModel) -> some View {
        HStack(spacing: 28) {
            Button { session.toggleListening() } label: {
                Image(systemName: session.state == .listening ? "mic.slash" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .liquidGlass(.regular, in: .circle)
            .accessibilityLabel(session.state == .listening ? "静音" : "开始聆听")

            Button { session.toggleListening() } label: {
                Image(systemName: session.state == .speaking ? "pause.fill" : "waveform")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(AppColor.accentGradient))
                    .shadow(color: AppColor.brandIndigo.opacity(0.38), radius: 18, y: 8)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("语音主控")

            Button { session.interrupt() } label: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .liquidGlass(.regular, in: .circle)
            .disabled(session.state != .speaking && session.state != .thinking)
            .opacity(session.state == .speaking || session.state == .thinking ? 1 : 0.45)
            .accessibilityLabel("打断回答")
        }
        .foregroundStyle(AppColor.primaryText)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .liquidGlass(.regular, in: .capsule)
        .glassHairline(cornerRadius: 44, opacity: 0.32)
    }
}

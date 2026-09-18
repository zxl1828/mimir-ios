import SwiftUI
import UIKit

/// 沉浸式语音模式。
///
/// 本批构建提供完整的界面与状态呈现；语音识别 / 合成的引擎接入
/// 在语音批次中完成（`VoiceSessionViewModel` 负责驱动下面这些状态）。
struct VoiceModeView: View {

    let chat: ChatViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var state: VoiceSessionState = .idle
    @State private var lines: [VoiceTranscriptLine] = []
    @State private var inputLevel: Double = 0
    @State private var outputLevel: Double = 0
    @State private var unavailable: VoiceUnavailableReason?
    @State private var pulseTimer: Task<Void, Never>?

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 1.15)

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 0)

                VoiceOrb(
                    state: state,
                    inputLevel: inputLevel,
                    outputLevel: outputLevel
                )

                Text(state.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(.top, 8)

                transcriptArea
                    .padding(.top, 18)

                Spacer(minLength: 0)

                if let unavailable {
                    unavailableCard(unavailable)
                } else {
                    controls
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .onAppear { prepare() }
        .onDisappear {
            pulseTimer?.cancel()
            state = .idle
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button {
                Haptics.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppColor.secondaryText.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出语音模式")

            Spacer()

            Text("语音对话")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 8)
    }

    // MARK: - 转写

    private var transcriptArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if lines.isEmpty {
                    Text("说点什么，我会在你说完后自动回应。")
                        .font(AppFont.hint)
                        .foregroundStyle(AppColor.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(lines) { line in
                    HStack {
                        if line.isUser { Spacer(minLength: 30) }
                        Text(line.text)
                            .font(AppFont.bubbleBody)
                            .foregroundStyle(line.isUser ? .white : AppColor.primaryText)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(line.isUser
                                          ? AnyShapeStyle(AppColor.accentGradient)
                                          : AnyShapeStyle(AppColor.secondaryText.opacity(0.10)))
                            )
                            .opacity(line.isFinal ? 1 : 0.72)
                        if !line.isUser { Spacer(minLength: 30) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 220)
        .scrollIndicators(.hidden)
    }

    // MARK: - 控制

    private var controls: some View {
        HStack(spacing: 26) {
            Button {
                Haptics.impact(.light)
                toggleListening()
            } label: {
                Image(systemName: state == .listening ? "pause.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(AppColor.accentGradient))
                    .shadow(color: AppColor.brandIndigo.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state == .listening ? "暂停聆听" : "开始说话")

            Button {
                Haptics.impact(.medium)
                interrupt()
            } label: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(AppColor.secondaryText.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(state != .speaking)
            .opacity(state == .speaking ? 1 : 0.45)
            .accessibilityLabel("打断")
        }
    }

    private func unavailableCard(_ reason: VoiceUnavailableReason) -> some View {
        VStack(spacing: 10) {
            Text(reason.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text(reason.detail)
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
            if reason.canOpenSettings {
                Button {
                    openSystemSettings()
                } label: {
                    Text("前往系统设置")
                        .font(AppFont.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(AppColor.accentGradient))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 18)
        .glassHairline(cornerRadius: 18)
    }

    // MARK: - 行为

    private func prepare() {
        // 语音引擎在语音批次接入；先展示界面与状态机，
        // 让用户明确知道当前处在哪一步，而不是点了没反应。
        state = .idle
        if !settings.hasUsableCredential {
            unavailable = .offline
        }
    }

    private func toggleListening() {
        if state == .listening {
            state = .idle
            pulseTimer?.cancel()
            inputLevel = 0
        } else {
            state = .listening
            startLevelPulse()
        }
    }

    private func interrupt() {
        state = .interrupted
        outputLevel = 0
        Haptics.notify(.warning)
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            state = .listening
        }
    }

    private func startLevelPulse() {
        pulseTimer?.cancel()
        pulseTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                await MainActor.run {
                    if state == .listening {
                        inputLevel = Double.random(in: 0.1...0.9)
                    }
                }
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

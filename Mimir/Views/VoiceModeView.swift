import SwiftUI
import SwiftData
import UIKit

/// 沉浸式语音模式。
///
/// 交互流程：进入即开始聆听 → 静音一段时间后自动提交 → 边生成边逐句朗读 →
/// 用户随时开口即可打断 → 回到聆听，形成连续对话。
struct VoiceModeView: View {

    let chat: ChatViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var session: VoiceSessionViewModel?
    @State private var isSummarizing = false

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 1.15)

            if let session {
                content(session)
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
        .onDisappear {
            session?.end()
        }
    }

    private func content(_ session: VoiceSessionViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(session)

            Spacer(minLength: 0)

            VoiceOrb(
                state: session.state,
                inputLevel: session.inputLevel,
                outputLevel: session.outputLevel
            )

            Text(session.state.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .padding(.top, 6)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: session.state)

            transcriptArea(session)
                .padding(.top, 16)

            Spacer(minLength: 0)

            if let reason = session.unavailable {
                unavailableCard(reason, session: session)
            } else {
                controls(session)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    // MARK: - 顶栏

    private func topBar(_ session: VoiceSessionViewModel) -> some View {
        HStack {
            Button {
                Haptics.impact(.light)
                session.end()
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

            VStack(spacing: 1) {
                Text("语音对话")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(session.usesBuiltInVoice ? "内置语音模型" : "系统语音合成")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            Spacer()

            Button {
                guard !isSummarizing else { return }
                isSummarizing = true
                Task {
                    await session?.generateMinutes()
                    isSummarizing = false
                }
            } label: {
                if isSummarizing {
                    ProgressView().controlSize(.small).tint(AppColor.primaryText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppColor.secondaryText.opacity(0.12)))
                } else {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppColor.secondaryText.opacity(0.12)))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("把这次语音整理成会议纪要")
        }
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            if let info = session.infoText {
                Text(info)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.warning)
                    .padding(.top, 6)
                    .offset(y: 20)
            }
        }
    }

    // MARK: - 转写

    private func transcriptArea(_ session: VoiceSessionViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if session.lines.isEmpty && session.partialText.isEmpty {
                        Text("说点什么，我会在你说完后自动回应。")
                            .font(AppFont.hint)
                            .foregroundStyle(AppColor.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(session.lines) { line in
                        bubble(line.isUser, text: line.text, isFinal: line.isFinal)
                            .id(line.id)
                    }

                    if !session.partialText.isEmpty {
                        bubble(true, text: session.partialText, isFinal: false)
                            .id("partial")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
            .scrollIndicators(.hidden)
            .onChange(of: session.lines.count) { _, _ in
                withAnimation(AppAnimation.bubble) {
                    proxy.scrollTo(session.lines.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private func bubble(_ isUser: Bool, text: String, isFinal: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 30) }
            Text(text)
                .font(AppFont.bubbleBody)
                .foregroundStyle(isUser ? .white : AppColor.primaryText)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isUser
                              ? AnyShapeStyle(AppColor.accentGradient)
                              : AnyShapeStyle(AppColor.secondaryText.opacity(0.10)))
                )
                .opacity(isFinal ? 1 : 0.72)
            if !isUser { Spacer(minLength: 30) }
        }
    }

    // MARK: - 控制

    private func controls(_ session: VoiceSessionViewModel) -> some View {
        HStack(spacing: 24) {
            Button {
                Haptics.impact(.light)
                session.toggleListening()
            } label: {
                Image(systemName: session.state == .listening ? "pause.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(AppColor.accentGradient))
                    .shadow(color: AppColor.brandIndigo.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.state == .listening ? "暂停聆听" : "开始说话")

            Button {
                Haptics.impact(.medium)
                session.interrupt()
            } label: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(AppColor.secondaryText.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(session.state != .speaking && session.state != .thinking)
            .opacity(session.state == .speaking || session.state == .thinking ? 1 : 0.45)
            .accessibilityLabel("打断")
        }
    }

    private func unavailableCard(
        _ reason: VoiceUnavailableReason,
        session: VoiceSessionViewModel
    ) -> some View {
        VStack(spacing: 10) {
            Text(reason.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text(reason.detail)
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
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

                Button {
                    Task { await session.start(conversation: chat.conversation) }
                } label: {
                    Text("重试")
                        .font(AppFont.chip)
                        .foregroundStyle(AppColor.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(AppColor.secondaryText.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 18)
        .glassHairline(cornerRadius: 18)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

import SwiftUI
import UIKit

/// 底部输入区：附件、多行输入、语音、发送 / 停止。
struct MessageInputBar: View {

    @Binding var text: String
    @Binding var attachments: [Data]
    var focus: FocusState<Bool>.Binding
    let isGenerating: Bool
    var placeholder: String = "发消息…"
    var onSend: () -> Void
    var onStop: () -> Void
    var onAttach: () -> Void
    var onVoice: () -> Void
    var onTextChanged: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }

            HStack(alignment: .bottom, spacing: 9) {
                attachButton

                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.bubbleBody)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1...6)
                    .focused(focus)
                    .submitLabel(.return)
                    .padding(.vertical, 8)
                    .onChange(of: text) { _, newValue in
                        onTextChanged(newValue)
                    }

                voiceButton
                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidGlassCard(cornerRadius: 26)
            .glassHairline(cornerRadius: 26)
        }
        .animation(AppAnimation.chip, value: attachments.count)
    }

    // MARK: - 子视图

    private var attachButton: some View {
        Button {
            Haptics.impact(.light)
            onAttach()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加图片")
    }

    private var voiceButton: some View {
        Button {
            Haptics.impact(.light)
            onVoice()
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("语音模式")
    }

    private var sendButton: some View {
        Button {
            if isGenerating {
                Haptics.impact(.medium)
                onStop()
            } else {
                Haptics.impact(.light)
                onSend()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(sendButtonFill)
                    .frame(width: 34, height: 34)
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: isGenerating ? 12 : 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isGenerating && !canSend)
        .animation(.easeInOut(duration: 0.18), value: isGenerating)
        .accessibilityLabel(isGenerating ? "停止生成" : "发送")
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var sendButtonFill: AnyShapeStyle {
        if isGenerating {
            return AnyShapeStyle(AppColor.danger.opacity(0.9))
        }
        return canSend
            ? AnyShapeStyle(AppColor.accentGradient)
            : AnyShapeStyle(AppColor.secondaryText.opacity(0.28))
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Haptics.impact(.light)
                                    attachments.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, Color.black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }
}

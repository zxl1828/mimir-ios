import SwiftUI
import UIKit

/// 输入框上需要响应硬件键盘的按键。
enum InputKeyCommand {
    case moveUp
    case moveDown
    case confirm
    case escape
}

/// 底部输入区：附件、多行输入、语音、发送 / 停止。
struct MessageInputBar: View {

    @Binding var text: String
    @Binding var attachments: [Data]
    var focus: FocusState<Bool>.Binding
    let isGenerating: Bool
    var placeholder: String = "发消息…"
    var onSend: () -> Void
    var onStop: () -> Void
    /// 附件菜单是否展开（由上层持有，方便菜单项触发相册 / 相机 / 扫描）。
    @Binding var showAttachMenu: Bool
    var onPickPhoto: () -> Void
    var onCamera: () -> Void
    var onScan: () -> Void
    var onVoice: () -> Void
    var onTextChanged: (String) -> Void = { _ in }
    /// 返回 true 表示该按键已被上层消费（例如技能选择器的高亮移动）。
    var onKeyCommand: (InputKeyCommand) -> Bool = { _ in false }

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
                    .onKeyPress(.upArrow) { onKeyCommand(.moveUp) ? .handled : .ignored }
                    .onKeyPress(.downArrow) { onKeyCommand(.moveDown) ? .handled : .ignored }
                    .onKeyPress(.return) { onKeyCommand(.confirm) ? .handled : .ignored }
                    .onKeyPress(.escape) { onKeyCommand(.escape) ? .handled : .ignored }

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
            showAttachMenu.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.primary.opacity(showAttachMenu ? 0.10 : 0.0001))
                )
                .contentShape(Circle())
                .rotationEffect(.degrees(showAttachMenu ? 45 : 0))
                .animation(AppAnimation.chip, value: showAttachMenu)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加图片")
        // 锚定在加号上，从按钮位置向上展开（iPhone 上也能保持气泡形态）。
        .popover(isPresented: $showAttachMenu, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            AttachmentMenu(
                onPickPhoto: { showAttachMenu = false; onPickPhoto() },
                onCamera: { showAttachMenu = false; onCamera() },
                onScan: { showAttachMenu = false; onScan() }
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
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

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
    @Environment(\.appAccent) private var accent
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

            HStack(alignment: .bottom, spacing: 8) {
                attachButton

                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppUI.body)
                    .foregroundStyle(AppUI.label)
                    .lineLimit(1...6)
                    .focused(focus)
                    .submitLabel(.return)
                    .padding(.vertical, 7)
                    .onChange(of: text) { _, newValue in
                        onTextChanged(newValue)
                    }
                    .onKeyPress(.upArrow) { onKeyCommand(.moveUp) ? .handled : .ignored }
                    .onKeyPress(.downArrow) { onKeyCommand(.moveDown) ? .handled : .ignored }
                    .onKeyPress(.return) { onKeyCommand(.confirm) ? .handled : .ignored }
                    .onKeyPress(.escape) { onKeyCommand(.escape) ? .handled : .ignored }

                trailingButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // Omni Bar：液态玻璃大圆角胶囊
            .liquidGlass(cornerRadius: 26, glowIntensity: 0.22)
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
                .foregroundStyle(AppUI.label2)
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

    /// 右侧单按钮：空输入 → 语音；有文字 → 蓝色圆形发送；生成中 → 停止。
    private var trailingButton: some View {
        Button {
            if isGenerating {
                Haptics.impact(.medium)
                onStop()
            } else if canSend {
                Haptics.impact(.light)
                onSend()
            } else {
                Haptics.impact(.light)
                onVoice()
            }
        } label: {
            ZStack {
                if isGenerating {
                    Circle()
                        .fill(AppUI.label.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppUI.label)
                } else if canSend {
                    Circle()
                        .fill(accent)
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppUI.label2)
                        .frame(width: 32, height: 32)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: canSend)
        .animation(.easeInOut(duration: 0.18), value: isGenerating)
        .accessibilityLabel(isGenerating ? "停止生成" : (canSend ? "发送" : "语音模式"))
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
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

import SwiftUI
import UIKit

/// 输入框上需要响应硬件键盘的按键。
enum InputKeyCommand {
    case moveUp
    case moveDown
    case confirm
    case escape
}

/// 底部悬浮调度输入栏（Dispatch Omni-Bar）：附件、多行输入、语音、发送 / 停止。
struct MessageInputBar: View {

    @Binding var text: String
    @Binding var attachments: [Data]
    var focus: FocusState<Bool>.Binding
    let isGenerating: Bool
    var placeholder: String = "询问 Mimir…"
    var onSend: () -> Void
    var onStop: () -> Void
    /// 附件菜单是否展开（由上层持有，方便菜单项触发相册 / 相机 / 扫描）。
    @Binding var showAttachMenu: Bool
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme
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

            HStack(alignment: .bottom, spacing: 10) {
                attachButton

                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppUI.body)
                    .foregroundStyle(AppUI.label)
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

                trailingButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(focus.wrappedValue ? 0.42 : 0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(focus.wrappedValue ? 0.18 : 0), lineWidth: 3)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: focus.wrappedValue)
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
                .foregroundStyle(AppUI.label)
                .frame(width: 36, height: 36)
                .background(showAttachMenu ? accent.opacity(0.16) : Color(uiColor: .tertiarySystemBackground), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 0.8)
                )
                .contentShape(Circle())
                .rotationEffect(.degrees(showAttachMenu ? 45 : 0))
                .animation(AppAnimation.chip, value: showAttachMenu)
        }
        .buttonStyle(StaticButtonFeedbackStyle())
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

    /// 右侧单按钮：空输入 → 语音；有文字 → 霓虹紫发光圆形发送；生成中 → 停止。
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
                        .fill(accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .strokeBorder(accent.opacity(0.6), lineWidth: 1)
                        )
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                } else if canSend {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent, AppUI.neonViolet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.9)
                        )
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(scheme == .dark ? 0.32 : 0.16),
                                    AppUI.neonViolet.opacity(scheme == .dark ? 0.22 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .strokeBorder(accent.opacity(0.45), lineWidth: 0.9)
                        )
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(StaticButtonFeedbackStyle())
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 0.8)
                            )
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Haptics.impact(.light)
                                    attachments.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, Color(red: 0.18, green: 0.12, blue: 0.32).opacity(0.75))
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

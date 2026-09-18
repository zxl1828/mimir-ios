import SwiftUI
import UIKit

/// 对话导出：选样式、看预览、保存到相册或分享出去。
struct ExportConversationSheet: View {

    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @State private var style: ShareCardStyle = .light
    @State private var preview: UIImage?
    @State private var isRendering = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("样式", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    previewArea

                    HStack(spacing: 12) {
                        Button {
                            Task { await save() }
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                                .font(AppFont.chip)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(AppColor.accentGradient))
                        }
                        .buttonStyle(.plain)
                        .disabled(preview == nil)

                        Button {
                            if let image = preview {
                                Haptics.impact(.light)
                                presentShareSheet([image])
                            }
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .font(AppFont.chip)
                                .foregroundStyle(AppColor.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(AppColor.secondaryText.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(preview == nil)
                    }

                    if let notice {
                        Text(notice)
                            .font(AppFont.hint)
                            .foregroundStyle(AppColor.secondaryText)
                    }

                    Text("图片在本机渲染，不会上传。长对话只导出最近 60 条消息。")
                        .font(AppFont.chipCompact)
                        .foregroundStyle(AppColor.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
            }
            .background(AppColor.canvas)
            .navigationTitle("导出为图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: style) { await renderPreview() }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.subtle.opacity(0.6))

            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
                    .padding(8)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(isRendering ? "正在渲染…" : "还没有内容可导出")
                        .font(AppFont.hint)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(.vertical, 60)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 240)
    }

    private func renderPreview() async {
        isRendering = true
        preview = ConversationImageExporter.render(conversation: conversation, style: style)
        isRendering = false
    }

    private func save() async {
        guard let image = preview ?? ConversationImageExporter.render(conversation: conversation, style: style) else {
            notice = "渲染失败，请稍后再试。"
            return
        }
        let saved = await ConversationImageExporter.saveToPhotos(image)
        notice = saved ? "已保存到相册。" : "保存失败，请检查相册权限后重试。"
        if saved { Haptics.notify(.success) } else { Haptics.notify(.error) }
    }
}

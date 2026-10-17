import SwiftUI
import SwiftData
import UIKit

/// Full-screen duplex voice conversation surface.
/// Delegates to the ADA-standard VoiceDuplexView.
struct VoiceConversationView: View {
    let chat: ChatViewModel

    var body: some View {
        VoiceDuplexView(chat: chat)
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
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void
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
                            Text(isLoading ? "正在整理本次语音转写" : errorMessage == nil ? "Generated from this voice session" : "无法生成会议纪要")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    Group {
                        if isLoading {
                            HStack(spacing: 12) {
                                ProgressView().tint(AppColor.brandPurple)
                                Text("正在生成纪要…").foregroundStyle(AppColor.secondaryText)
                            }
                        } else if let errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(errorMessage).foregroundStyle(AppColor.primaryText)
                                Button("重新生成", action: onRetry)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColor.brandPurple)
                            }
                        } else {
                            Text(text.isEmpty ? "模型没有返回可显示的纪要。" : text)
                                .foregroundStyle(AppColor.primaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 16, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .liquidGlass(.regular, in: .rect(cornerRadius: 22))
                    .glassHairline(cornerRadius: 22, opacity: 0.34)
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
                    .disabled(isLoading || text.isEmpty)
                }
            }
        }
    }
}

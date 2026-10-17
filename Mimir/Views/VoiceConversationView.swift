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

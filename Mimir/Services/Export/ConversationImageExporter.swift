import SwiftUI
import UIKit
import Photos

/// 长图样式。
enum ShareCardStyle: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var background: Color {
        self == .dark
            ? Color(red: 0.06, green: 0.06, blue: 0.08)
            : Color(red: 0.97, green: 0.97, blue: 0.99)
    }

    var cardBackground: Color {
        self == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.16)
            : Color.white
    }

    var hairline: Color {
        self == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    var primaryText: Color {
        self == .dark
            ? Color(red: 0.96, green: 0.96, blue: 0.98)
            : Color(red: 0.07, green: 0.07, blue: 0.09)
    }

    var secondaryText: Color {
        self == .dark
            ? Color(red: 0.62, green: 0.62, blue: 0.68)
            : Color(red: 0.43, green: 0.43, blue: 0.48)
    }
}

/// 把一段对话在本地渲染成一张长图。
///
/// 全程离屏渲染，不依赖任何环境对象，也不上传任何内容。
/// 渲染固定使用 780pt 宽度，否则长图排版会塌。
@MainActor
enum ConversationImageExporter {

    /// 导出内容宽度（pt）。
    static let contentWidth: CGFloat = 780
    /// 一张长图最多容纳的消息条数。
    static let maximumMessageCount = 60
    /// 估算高度上限（pt）：超过就继续丢弃较早的消息，避免渲染爆内存。
    static let maximumEstimatedHeight: CGFloat = 11000

    // MARK: - 渲染

    /// 渲染长图；没有任何可导出内容时返回 nil。
    static func render(conversation: Conversation, style: ShareCardStyle) -> UIImage? {
        let all = conversation.orderedMessages
        let picked = pickMessages(from: all)
        guard !picked.isEmpty else { return nil }

        let card = ConversationShareCard(
            title: conversation.title,
            messages: picked,
            style: style,
            exportedAt: Date(),
            omittedCount: max(0, all.count - picked.count)
        )
        .frame(width: contentWidth)
        .environment(\.colorScheme, style.colorScheme)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// 挑选要导出的消息：先截取最近 N 条，再按估算高度继续收缩。
    static func pickMessages(from all: [ChatMessage]) -> [ChatMessage] {
        var picked = Array(all.suffix(maximumMessageCount))
        while picked.count > 1, estimateHeight(picked) > maximumEstimatedHeight {
            picked.removeFirst()
        }
        return picked
    }

    /// 粗略估算渲染高度，宁可高估，避免一张图过高导致内存压力。
    static func estimateHeight(_ messages: [ChatMessage]) -> CGFloat {
        var total: CGFloat = 240
        for message in messages {
            let body = message.renderedText
            let lines = max(1, Int(ceil(Double(body.count) / 28.0)))
            total += 64 + CGFloat(lines) * 24
            if message.attachmentData != nil { total += 260 }
            if !message.thinkingText.isEmpty { total += 90 }
        }
        return total
    }

    // MARK: - 保存到相册

    /// `UIImage` 在严格并发下的传递包装：图片本身是只读的，跨隔离域安全。
    private struct ImageBox: @unchecked Sendable {
        let image: UIImage
    }

    /// 写入系统相册（仅新增权限）。
    static func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        let box = ImageBox(image: image)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: box.image)
            }
            return true
        } catch {
            return false
        }
    }
}

/// 导出用的卡片视图：一次性渲染，不读取任何注入环境。
struct ConversationShareCard: View {

    let title: String
    let messages: [ChatMessage]
    let style: ShareCardStyle
    let exportedAt: Date
    let omittedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ForEach(messages) { message in
                bubble(for: message)
            }

            footer
        }
        .padding(28)
        .background(style.background)
    }

    // MARK: - 头尾

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryText)

            HStack(spacing: 8) {
                Text("\(messages.count) 条消息")
                Text("·")
                Text(exportedAt, format: .dateTime.year().month().day().hour().minute())
                if omittedCount > 0 {
                    Text("·")
                    Text("已省略较早的 \(omittedCount) 条")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(style.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.hairline)
                .frame(height: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("由 Mimir 导出 · 内容仅在本机渲染")
                .font(.system(size: 12))
                .foregroundStyle(style.secondaryText)
            Spacer(minLength: 0)
            Text("mimir-ios")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(style.secondaryText)
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(style.hairline)
                .frame(height: 1)
        }
    }

    // MARK: - 消息

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        if message.role == .user {
            userBubble(message)
        } else {
            assistantBubble(message)
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 120)

            VStack(alignment: .trailing, spacing: 6) {
                if let data = message.attachmentData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppColor.accentGradient)
                        )
                }

                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
            }
        }
    }

    private func assistantBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.thinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message.thinkingText)
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(AppColor.brandPurple.opacity(0.45))
                            .frame(width: 2.5)
                    }
            }

            MarkdownText(raw: ExportTextSanitizer.sanitize(message.renderedText))

            HStack(spacing: 8) {
                if !message.agentName.isEmpty {
                    Text(message.agentName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.brandIndigo)
                }
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(style.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style.hairline, lineWidth: 1)
        }
        .environment(\.colorScheme, style.colorScheme)
    }
}

/// 导出前的文本降级处理。
///
/// Markdown 渲染器里的公式块与 Mermaid 图会走 `WKWebView`，离屏渲染时
/// 拿不到内容（还可能带来额外开销），所以导出前把它们降级成纯文本。
enum ExportTextSanitizer {

    static func sanitize(_ raw: String) -> String {
        demoteMathAndDiagrams(raw)
    }

    private static func demoteMathAndDiagrams(_ raw: String) -> String {
        var output: [String] = []
        var inMath = false
        var inDiagram = false

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inDiagram {
                output.append(line)
                if trimmed == "```" { inDiagram = false }
                continue
            }

            if !inMath, trimmed.lowercased() == "```mermaid" {
                inDiagram = true
                output.append("```text")
                output.append("（Mermaid 图表源码）")
                continue
            }

            if inMath {
                if let closing = line.range(of: "$$") {
                    let body = String(line[line.startIndex..<closing.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    if !body.isEmpty { output.append("〔公式〕" + body) }
                    inMath = false
                } else {
                    let body = trimmed
                    if !body.isEmpty { output.append("〔公式〕" + body) }
                }
                continue
            }

            if trimmed.hasPrefix("$$") {
                let remainder = String(trimmed.dropFirst(2))
                if let closing = remainder.range(of: "$$") {
                    let body = String(remainder[remainder.startIndex..<closing.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    if !body.isEmpty { output.append("〔公式〕" + body) }
                } else {
                    inMath = true
                    let body = remainder.trimmingCharacters(in: .whitespaces)
                    if !body.isEmpty { output.append("〔公式〕" + body) }
                }
                continue
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }
}

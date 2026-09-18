import SwiftUI
import UIKit

/// 轻量 Markdown 渲染器。
///
/// 覆盖对话里真正会用到的语法：标题、段落、有序 / 无序列表、引用、
/// 分隔线、围栏代码块、行内代码与表格。解析是纯文本操作，
/// 不依赖任何第三方库，因此可以在流式输出过程中逐块增量重绘。
struct MarkdownText: View {

    let raw: String
    var isStreaming: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let blocks = MarkdownBlock.parse(raw)
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isLast: index == blocks.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isLast: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(let text):
            Text(inline(text))
                .font(AppFont.bubbleBody)
                .foregroundStyle(AppColor.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(AppColor.secondaryText)
                    .frame(width: 5, height: 5)
                    .offset(y: -2)
                Text(inline(text))
                    .font(AppFont.bubbleBody)
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.brandIndigo)
                    .frame(minWidth: 18, alignment: .leading)
                Text(inline(text))
                    .font(AppFont.bubbleBody)
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColor.brandIndigo.opacity(0.55))
                    .frame(width: 3)
                Text(inline(text))
                    .font(AppFont.bubbleBody)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .divider:
            Divider().opacity(0.5)

        case .code(let language, let content):
            CodeBlockView(language: language, code: content)

        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .raw(let text):
            Text(text)
                .font(AppFont.bubbleBody)
                .foregroundStyle(AppColor.primaryText)
        }

        if isStreaming && isLast {
            StreamingCursor()
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 21
        case 2: return 19
        case 3: return 17.5
        default: return 16.5
        }
    }

    private func inline(_ text: String) -> AttributedString {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return AttributedString(text)
        }
        return parsed
    }
}

/// 流式输出时的光标。
struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(AppColor.brandIndigo)
            .frame(width: 9, height: 16)
            .opacity(visible ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - 块解析

enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(marker: String, text: String)
    case quote(String)
    case divider
    case code(language: String, content: String)
    case table(header: [String], rows: [[String]])
    case raw(String)

    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var paragraphBuffer: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 围栏代码块
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language, content: codeLines.joined(separator: "\n")))
                index += 1
                continue
            }

            // 空行
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            // 表格
            if isTableRow(trimmed), index + 1 < lines.count,
               isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                let header = splitTableRow(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(candidate) else { break }
                    rows.append(splitTableRow(candidate))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // 标题
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }
                let level = min(hashes.count, 4)
                let text = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    flushParagraph()
                    blocks.append(.heading(level: level, text: text))
                    index += 1
                    continue
                }
            }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(candidate.dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // 无序列表
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                index += 1
                continue
            }

            // 有序列表
            if let match = firstNumberedMarker(in: trimmed) {
                flushParagraph()
                blocks.append(.numbered(marker: match.marker, text: match.rest))
                index += 1
                continue
            }

            paragraphBuffer.append(line)
            index += 1
        }

        flushParagraph()
        return blocks.isEmpty ? [.raw(raw)] : blocks
    }

    private static func isTableRow(_ line: String) -> Bool {
        guard line.hasPrefix("|") else { return false }
        return line.filter { $0 == "|" }.count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let stripped = line.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var content = line
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func firstNumberedMarker(in line: String) -> (marker: String, rest: String)? {
        var digits = ""
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor].isNumber {
            digits.append(line[cursor])
            cursor = line.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < line.endIndex else { return nil }
        let separator = line[cursor]
        guard separator == "." || separator == "、" || separator == ")" else { return nil }
        let afterSeparator = line.index(after: cursor)
        let rest = line[afterSeparator...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return ("\(digits)\(separator)", rest)
    }
}

// MARK: - 代码块

struct CodeBlockView: View {

    let language: String
    let code: String

    @State private var copied = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "代码" : language.lowercased())
                    .font(AppFont.codeSmall)
                    .foregroundStyle(AppColor.secondaryText)
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = code
                    Haptics.impact(.light)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(AppFont.codeSmall)
                    .foregroundStyle(copied ? AppColor.success : AppColor.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(AppFont.code)
                    .foregroundStyle(AppColor.primaryText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.05)
                      : Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColor.separator.opacity(0.35), lineWidth: 0.7)
        )
    }
}

// MARK: - 表格

struct MarkdownTableView: View {

    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(header, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, values in
                    Divider().opacity(index == rows.count - 1 ? 0 : 0.35)
                    row(values, isHeader: false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.subtle.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColor.separator.opacity(0.3), lineWidth: 0.7)
            )
        }
    }

    private func row(_ values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(isHeader ? .system(size: 13.5, weight: .semibold) : .system(size: 13.5))
                    .foregroundStyle(isHeader ? AppColor.primaryText : AppColor.secondaryText)
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: 74, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)

                if index != values.count - 1 {
                    Divider().frame(height: 18).opacity(0.35)
                }
            }
        }
    }
}

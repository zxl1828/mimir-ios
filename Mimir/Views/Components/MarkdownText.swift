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

    @Environment(\.appAccent) private var accent

    var body: some View {
        if isStreaming {
            streamingBody
        } else {
            parsedBody
        }
    }

    /// 流式期间的轻量渲染。
    private var streamingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(raw)
                .font(AppUI.body)
                .foregroundStyle(AppUI.label)
                .fixedSize(horizontal: false, vertical: true)
            StreamingCursor()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 生成结束后的完整 Markdown 渲染（代码块 / 表格 / LaTeX 等）。
    private var parsedBody: some View {
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
                .foregroundStyle(AppUI.label)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(let text):
            Text(inline(text))
                .font(AppUI.body)
                .foregroundStyle(AppUI.label)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .offset(y: -2)
                Text(inline(text))
                    .font(AppUI.body)
                    .foregroundStyle(AppUI.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(minWidth: 18, alignment: .leading)
                Text(inline(text))
                    .font(AppUI.body)
                    .foregroundStyle(AppUI.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent.opacity(0.65))
                    .frame(width: 3)
                Text(inline(text))
                    .font(AppUI.body)
                    .foregroundStyle(AppUI.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .divider:
            Divider().opacity(0.5)

        case .code(let language, let content):
            if language.lowercased() == "mermaid" {
                MermaidBlockView(source: content)
            } else {
                CodeBlockView(language: language, code: content)
            }

        case .math(let latex):
            LatexBlockView(source: latex)

        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .raw(let text):
            Text(text)
                .font(AppUI.body)
                .foregroundStyle(AppUI.label)
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
    @Environment(\.appAccent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(accent)
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
    case math(String)
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

            // 独立成行的数学公式块
            if trimmed.hasPrefix("$$") {
                flushParagraph()
                let remainder = String(trimmed.dropFirst(2))
                if remainder.hasSuffix("$$"), remainder.count > 2 {
                    let body = String(remainder.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.math(body))
                    index += 1
                    continue
                }
                var formulaLines: [String] = []
                if !remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                    formulaLines.append(remainder)
                }
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasSuffix("$$") {
                        let body = String(candidate.dropLast(2)).trimmingCharacters(in: .whitespaces)
                        if !body.isEmpty { formulaLines.append(body) }
                        index += 1
                        break
                    }
                    formulaLines.append(lines[index])
                    index += 1
                }
                blocks.append(.math(formulaLines.joined(separator: "\n")))
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

// MARK: - Codex 终端代码块（macOS 三色圆点 + 语言胶囊 + 一键复制 + 行号 + 液态玻璃折射边）

struct CodeBlockView: View {

    let language: String
    let code: String

    @State private var copied = false
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    private var lines: [String] {
        let split = code.components(separatedBy: "\n")
        return split.last == "" ? Array(split.dropLast()) : split
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar

            Rectangle()
                .fill(accent.opacity(scheme == .dark ? 0.24 : 0.16))
                .frame(height: 0.6)

            codeArea
        }
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    scheme == .dark
                        ? Color(red: 0.05, green: 0.04, blue: 0.10).opacity(0.84)
                        : Color(red: 0.96, green: 0.95, blue: 0.99)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
        )
        .interactiveTilt(maxAngle: 4.5, cornerRadius: 15)
    }

    // MARK: - 终端标题栏

    private var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                trafficLight(Color(red: 1.00, green: 0.37, blue: 0.34))
                trafficLight(Color(red: 1.00, green: 0.75, blue: 0.22))
                trafficLight(Color(red: 0.24, green: 0.82, blue: 0.38))
            }

            Spacer(minLength: 4)

            // 语言标签胶囊（对齐参考图 CS+ 标签）
            Text(language.isEmpty ? "code" : language.lowercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppUI.label2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppUI.fill)
                )

            Button {
                copyCode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "square.on.square")
                    Text(copied ? "已复制" : "1-tap Copy")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? Color(red: 0.20, green: 0.80, blue: 0.40) : AppUI.label)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(copied
                              ? AnyShapeStyle(Color(red: 0.20, green: 0.80, blue: 0.40).opacity(0.18))
                              : AnyShapeStyle(AppUI.fill))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            copied ? Color(red: 0.20, green: 0.80, blue: 0.40).opacity(0.45) : accent.opacity(0.22),
                            lineWidth: 0.6
                        )
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PhysicalElasticCapsuleButtonStyle())
            .animation(.easeInOut(duration: 0.2), value: copied)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            scheme == .dark
                ? Color.white.opacity(0.03)
                : accent.opacity(0.04)
        )
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.88))
            .frame(width: 9.5, height: 9.5)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - 代码区（行号 + 横向滚动）

    private var codeArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 11) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppUI.label3.opacity(0.70))
                            .frame(height: 19)
                    }
                }
                .padding(.trailing, 4)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(accent.opacity(0.20))
                        .frame(width: 0.6)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(AppUI.label)
                            .frame(height: 19, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        Haptics.impact(.light)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

// MARK: - 表格

struct MarkdownTableView: View {

    let header: [String]
    let rows: [[String]]

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

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
                    .fill(scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 0.8)
            )
        }
    }

    private func row(_ values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(isHeader ? .system(size: 13.5, weight: .semibold) : .system(size: 13.5))
                    .foregroundStyle(isHeader ? AppUI.label : AppUI.label2)
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

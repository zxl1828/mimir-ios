import Foundation

/// 极简 Server-Sent Events 解析器。
///
/// 只处理两种协议都会用到的最小集合：`data:` 行累积、`event:` 名称、
/// 空行作为一条事件的分隔。注释行（以 `:` 开头）直接忽略。
struct SSEParser {

    private var dataLines: [String] = []
    private var eventName: String?

    /// 送入一行文本，若构成完整事件则返回 (event, data)。
    mutating func consume(line: String) -> (event: String?, data: String)? {
        let trimmedLine = line.hasSuffix("\r") ? String(line.dropLast()) : line

        if trimmedLine.isEmpty {
            guard !dataLines.isEmpty || eventName != nil else { return nil }
            let payload = dataLines.joined(separator: "\n")
            let event = eventName
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
            return (event, payload)
        }

        if trimmedLine.hasPrefix(":") { return nil }

        guard let separatorIndex = trimmedLine.firstIndex(of: ":") else { return nil }
        let field = String(trimmedLine[trimmedLine.startIndex..<separatorIndex])
        var value = String(trimmedLine[trimmedLine.index(after: separatorIndex)...])
        if value.hasPrefix(" ") { value.removeFirst() }

        switch field {
        case "data":
            dataLines.append(value)
        case "event":
            eventName = value
        default:
            break
        }
        return nil
    }

    /// 流结束时冲刷残留数据。
    mutating func flush() -> (event: String?, data: String)? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        let event = eventName
        eventName = nil
        return (event, payload)
    }
}

import Foundation
import SwiftData

/// 记忆整理：**只在用户明确要求时才写入**。
///
/// 这里以前是"抽取式记忆"——扫描最近 20 条消息，把「我叫…」「我喜欢…」
/// 这类表述统统存下来，结果越记越多。现在只认明确指令
/// （「记住…」「别忘…」「remember this」等）：一条指令都没有就什么都不写。
@MainActor
enum MemoryExtractor {

    /// 触发写入的记忆指令（中英，长词优先匹配）。
    private static let triggers: [String] = [
        "保存到记忆", "存入记忆", "加入记忆", "帮我记住", "帮我记", "记录一下", "记一下",
        "记住", "记下", "记牢", "别忘了", "不要忘", "别忘",
        "remember this", "remember that", "keep in mind", "don't forget", "dont forget", "note that"
    ].sorted { $0.count > $1.count }

    /// 回顾一段对话：只有用户明确要求记住的内容才会落地。返回新增条数。
    @discardableResult
    static func review(
        conversation: Conversation,
        context: ModelContext,
        store: MemoryStore? = nil
    ) -> Int {
        let userMessages = conversation.orderedMessages
            .filter { $0.role == .user }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !userMessages.isEmpty else { return 0 }

        var candidates: [(text: String, quote: String, source: ChatMessage)] = []
        for message in userMessages.suffix(20) {
            for fact in explicitFacts(in: message.text) {
                candidates.append((fact, message.text, message))
            }
        }

        // 没有明确指令：一条都不记。
        guard !candidates.isEmpty else { return 0 }

        let existing = (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? []
        var inserted = 0

        for candidate in candidates {
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 4 else { continue }

            if isDuplicate(text, among: existing) { continue }

            let entry = MemoryEntry(
                text: text,
                summary: String(text.prefix(60)),
                sourceConversationID: conversation.id,
                sourceConversationTitle: conversation.title,
                sourceMessageID: candidate.source.id,
                sourceQuote: String(candidate.quote.prefix(160)),
                tags: [],
                localOnly: false,
                importance: 0.7,
                isAutoExtracted: false
            )
            context.insert(entry)
            store?.upsert(entry: entry, context: context)
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
        }
        return inserted
    }

    // MARK: - 指令解析

    /// 命中记忆指令时，返回指令之外的正文（每条一段）；没命中返回空数组。
    static func explicitFacts(in text: String) -> [String] {
        let lowered = text.lowercased()
        guard triggers.contains(where: { lowered.contains($0) }) else { return [] }

        var cleaned = text
        for trigger in triggers {
            cleaned = cleaned.replacingOccurrences(of: trigger, with: "\n", options: [.caseInsensitive])
        }

        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: "\n。！？!?;；"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t:：,，-—、")) }
            .filter { $0.count >= 2 && $0.count <= 200 }
    }

    private static func isDuplicate(_ text: String, among existing: [MemoryEntry]) -> Bool {
        let normalized = normalizedForm(text)
        for entry in existing {
            let other = normalizedForm(entry.text)
            if other == normalized { return true }
            if !other.isEmpty, normalized.contains(other), other.count >= 8 { return true }
            if !normalized.isEmpty, other.contains(normalized), normalized.count >= 8 { return true }
        }
        return false
    }

    private static func normalizedForm(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }

}

/// 长对话摘要：超出上下文窗口时生成滚动摘要，而不是简单截断。
@MainActor
enum ConversationSummarizer {

    /// 保留的最近消息条数（这些不进入摘要）。
    static let recentWindow = 12
    /// 累计多少条未摘要消息后触发一次整理。
    static let triggerCount = 24

    static func shouldSummarize(_ conversation: Conversation) -> Bool {
        let messages = conversation.orderedMessages.filter { !$0.isStreaming }
        let summarized = conversation.summarizedUpToIndex
        let pending = messages.filter { $0.orderIndex > summarized }
        return pending.count >= triggerCount && messages.count > recentWindow
    }

    /// 生成并写回滚动摘要。
    @discardableResult
    static func summarize(
        conversation: Conversation,
        credential: APICredential,
        parameters: ModelParameters
    ) async -> Bool {
        let messages = conversation.orderedMessages.filter { !$0.isStreaming }
        guard messages.count > recentWindow else { return false }

        let older = messages.dropLast(recentWindow)
        guard let lastIncluded = older.last else { return false }

        let transcript = older
            .map { "\($0.role == .user ? "用户" : "助手")：\($0.text)" }
            .joined(separator: "\n")
            .suffix(12_000)

        let previous = conversation.rollingSummary
        let prompt = """
        请把下面这段对话压缩成一段背景摘要，供后续继续对话时使用。
        要求：保留关键事实、结论、未完成的待办与用户的偏好；去掉寒暄与重复内容；不超过 300 字；直接输出摘要正文。

        \(previous.isEmpty ? "" : "此前的摘要：\n\(previous)\n")
        新增对话：
        \(transcript)
        """

        var request = parameters
        request.streamsResponse = false
        request.maxTokens = min(parameters.maxTokens, 800)
        request.temperature = 0.2
        request.systemPrompt = "你负责压缩对话历史，输出简洁客观的中文摘要。"
        request.modelID = conversation.modelID.isEmpty ? parameters.modelID : conversation.modelID

        let client = LLMClientFactory.make(for: credential)
        var collected = ""

        do {
            let stream = client.streamChat(
                messages: [LLMChatMessage(role: .user, text: prompt)],
                parameters: request,
                credential: credential,
                tools: []
            )
            for try await event in stream {
                if case .textDelta(let chunk) = event { collected += chunk }
                if case .finished = event { break }
            }
        } catch {
            return false
        }

        let summary = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return false }

        conversation.rollingSummary = summary
        conversation.summarizedUpToIndex = lastIncluded.orderIndex
        return true
    }
}

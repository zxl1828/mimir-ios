import Foundation
import SwiftData

/// 后台记忆整理。
///
/// 以纯端侧的规则抽取打底（保证任何设备上都可用、零网络），
/// 在端侧语言模型可用时再做一次语义提炼。
@MainActor
enum MemoryExtractor {

    /// 回顾一段对话，沉淀值得长期记住的信息。返回新增条数。
    @discardableResult
    static func review(
        conversation: Conversation,
        context: ModelContext,
        store: MemoryStore? = nil
    ) async -> Int {
        let userMessages = conversation.orderedMessages
            .filter { $0.role == .user }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !userMessages.isEmpty else { return 0 }

        var candidates: [(text: String, quote: String, source: ChatMessage)] = []
        for message in userMessages.suffix(20) {
            for fact in ruleBasedFacts(in: message.text) {
                candidates.append((fact, message.text, message))
            }
        }

        if candidates.count < 3,
           let refined = await semanticFacts(from: userMessages.suffix(6).map(\.text)) {
            for fact in refined {
                candidates.append((fact, "", userMessages.last!))
            }
        }

        guard !candidates.isEmpty else { return 0 }

        let existing = (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? []
        var inserted = 0

        for candidate in candidates {
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 6 else { continue }

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
                importance: 0.55,
                isAutoExtracted: true
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

    // MARK: - 规则抽取

    /// 从一句话里挑出长期有价值的事实型表述。
    static func ruleBasedFacts(in text: String) -> [String] {
        let patterns: [(String, String)] = [
            ("记住", "需要记住的信息"),
            ("我叫", "称呼"),
            ("我的名字", "称呼"),
            ("我是", "身份"),
            ("我在", "所在地或所属"),
            ("我住", "居住地"),
            ("我喜欢", "偏好"),
            ("我不喜欢", "忌讳"),
            ("我习惯", "工作习惯"),
            ("我通常", "工作习惯"),
            ("我的目标", "目标"),
            ("我打算", "计划"),
            ("我计划", "计划"),
            ("以后都", "长期要求"),
            ("每次都要", "长期要求"),
            ("我的项目", "项目背景"),
            ("我的公司", "工作背景"),
            ("我的团队", "工作背景"),
            ("我的生日", "纪念日"),
            ("生病", "健康情况"),
            ("过敏", "健康情况")
        ]

        var facts: [String] = []
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n;；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for sentence in sentences {
            for (trigger, category) in patterns where sentence.contains(trigger) {
                let fact = sentence
                    .replacingOccurrences(of: "记住", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard fact.count >= 4, fact.count <= 120 else { continue }
                facts.append("[\(category)] \(fact)")
                break
            }
        }
        return facts
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

    // MARK: - 端侧语义提炼

    private static func semanticFacts(from messages: [String]) async -> [String]? {
        guard !messages.isEmpty else { return nil }
        let joined = messages.suffix(6).joined(separator: "\n")
        let prompt = """
        下面是用户说过的几句话。请抽取其中值得长期记住的用户事实（身份、偏好、习惯、目标、长期要求）。
        每行一条，最多 3 条，直接写事实本身，不要编号，不要解释。
        如果没有任何值得长期记住的内容，只输出 none。

        \(joined)
        """
        guard let output = await OnDeviceLanguageModel.generate(prompt: prompt, maxTokens: 220) else {
            return nil
        }
        let facts = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line -> String in
                var value = line
                while let first = value.first, first.isNumber || first == "-" || first == "•" || first == "." {
                    value.removeFirst()
                }
                return value.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty && $0.lowercased() != "none" && $0.count >= 4 }
        return facts.isEmpty ? nil : Array(facts.prefix(3))
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

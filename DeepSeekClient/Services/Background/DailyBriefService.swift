import Foundation
import SwiftData

/// 后台生成当日简报，并写入一个本地对话，方便打开 App 就能看到。
@MainActor
enum DailyBriefService {

    /// 生成今日简报。返回是否成功。
    @discardableResult
    static func generateBrief() async -> Bool {
        let settings = AppSettings()
        let credential = settings.resolvedCredential
        guard !credential.key.isEmpty else { return false }

        let storeURL = URL.applicationSupportDirectory.appending(path: "DeepSeekClient.store")
        guard let container = try? ModelContainer(for: Conversation.self, ChatMessage.self, configurations: ModelConfiguration(url: storeURL)) else {
            return false
        }
        let context = container.mainContext

        let prompt = """
        请生成今天的简报，包含：
        1. 一句今日概览
        2. 三条值得关注的通用提醒（工作日安排、待办梳理、效率建议）
        只输出正文，不要解释你是什么模型。
        """

        var parameters = settings.parameters
        parameters.streamsResponse = false
        parameters.maxTokens = min(parameters.maxTokens, 700)
        parameters.systemPrompt = "你是一位简洁高效的日程助手。"

        let client = LLMClientFactory.make(for: credential)
        var collected = ""
        do {
            let stream = client.streamChat(
                messages: [LLMChatMessage(role: .user, text: prompt)],
                parameters: parameters,
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

        let text = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        let title = "每日简报 · \(formatter.string(from: Date()))"

        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.title == title }
        )
        let existing = (try? context.fetch(descriptor)) ?? []

        let conversation: Conversation
        if let first = existing.first {
            for message in first.messages { context.delete(message) }
            conversation = first
        } else {
            conversation = Conversation(title: title, modelID: parameters.modelID)
            context.insert(conversation)
        }

        let message = ChatMessage(
            role: .assistant,
            text: text,
            orderIndex: 0,
            thinkingMode: .quick
        )
        message.agentName = "每日简报"
        context.insert(message)
        message.conversation = conversation
        conversation.updatedAt = Date()

        try? context.save()
        return true
    }

    /// 后台轻量刷新：只做本地维护（清理过期会话、整理记忆索引）。
    @discardableResult
    static func refreshInBackground() async -> Bool {
        let settings = AppSettings()
        guard let cutoff = settings.retention.cutoff else { return true }

        let storeURL = URL.applicationSupportDirectory.appending(path: "DeepSeekClient.store")
        guard let container = try? ModelContainer(for: Conversation.self, configurations: ModelConfiguration(url: storeURL)) else {
            return false
        }
        let context = container.mainContext
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.isPinned == false }
        )
        guard let conversations = try? context.fetch(descriptor) else { return false }
        var removed = false
        for conversation in conversations where conversation.usesAutoDelete && conversation.updatedAt < cutoff {
            context.delete(conversation)
            removed = true
        }
        if removed { try? context.save() }
        return true
    }
}

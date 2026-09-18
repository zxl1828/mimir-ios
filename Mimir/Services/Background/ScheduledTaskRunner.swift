import Foundation
import SwiftData

/// 主 ModelContainer 的共享引用：后台任务在主进程内被唤醒时，
/// 需要复用同一个容器，而不是另开一份数据库文件。
@MainActor
enum AppContainer {
    static var shared: ModelContainer?
}

/// 定时任务的执行器：组装提示词 → 调用云端模型 → 把结果写成一段新对话。
@MainActor
enum ScheduledTaskRunner {

    // MARK: - 后台入口

    /// 后台被唤醒时调用：执行所有到期任务，并重新安排下一次唤醒。
    @discardableResult
    static func runDueTasks() async -> Bool {
        let settings = AppSettings()
        guard settings.hasUsableCredential else { return false }
        guard let container = AppContainer.shared else { return false }
        let context = container.mainContext

        let descriptor = FetchDescriptor<ScheduledTask>(
            sortBy: [SortDescriptor(\ScheduledTask.hour), SortDescriptor(\ScheduledTask.minute)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []

        var anySucceeded = false
        for task in tasks where task.isDue() {
            let ok = await run(task, context: context, settings: settings)
            anySucceeded = anySucceeded || ok
        }

        BackgroundTaskScheduler.reschedule(tasks: tasks)
        return anySucceeded
    }

    /// 冷启动时调用，保证下一次唤醒已经排上。
    static func rescheduleFromStore() {
        guard let container = AppContainer.shared else { return }
        let context = container.mainContext
        let tasks = (try? context.fetch(FetchDescriptor<ScheduledTask>())) ?? []
        BackgroundTaskScheduler.reschedule(tasks: tasks)
    }

    // MARK: - 单次执行

    @discardableResult
    static func run(
        _ task: ScheduledTask,
        context: ModelContext,
        settings: AppSettings
    ) async -> Bool {
        let prompt = task.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            task.lastError = "任务内容为空。"
            try? context.save()
            return false
        }

        let credential = settings.resolvedCredential
        guard !credential.key.isEmpty else {
            task.lastError = "还没有配置 API Key。"
            try? context.save()
            return false
        }

        var parameters = settings.parameters.applying(task.thinkingMode)
        parameters.streamsResponse = false
        parameters.maxTokens = min(parameters.maxTokens, 2_048)
        parameters.modelID = credential.modelID

        var systemParts: [String] = [settings.parameters.systemPrompt]
        if let agent = fetchAgent(named: task.agentName, context: context), !agent.systemPrompt.isEmpty {
            systemParts.append("当前智能体：\(agent.name)\n\(agent.systemPrompt)")
        }
        if let skill = fetchSkill(named: task.skillName, context: context), !skill.promptPrefix.isEmpty {
            systemParts.append("当前技能：\(skill.name)\n\(skill.promptPrefix)")
        }
        systemParts.append("这是一次定时任务，直接输出可阅读的结果，不要反问澄清。")
        parameters.systemPrompt = systemParts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

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
            task.lastError = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            try? context.save()
            return false
        }

        let result = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            task.lastError = "模型没有返回内容。"
            try? context.save()
            return false
        }

        let conversation = makeConversation(for: task, context: context)

        let userMessage = ChatMessage(
            role: .user,
            text: prompt,
            orderIndex: 0,
            thinkingMode: task.thinkingMode
        )
        userMessage.agentName = task.agentName
        userMessage.skillName = task.skillName
        context.insert(userMessage)
        userMessage.conversation = conversation

        let assistantMessage = ChatMessage(
            role: .assistant,
            text: result,
            orderIndex: 1,
            thinkingMode: task.thinkingMode
        )
        assistantMessage.agentName = task.agentName.isEmpty ? "定时任务" : task.agentName
        context.insert(assistantMessage)
        assistantMessage.conversation = conversation

        task.lastRunAt = Date()
        task.lastError = ""
        task.runCount += 1
        task.lastResultConversationID = conversation.id
        conversation.updatedAt = Date()

        try? context.save()

        if settings.memoryEnabled && settings.backgroundMemoryReview {
            _ = await MemoryExtractor.review(conversation: conversation, context: context, store: nil)
        }
        return true
    }

    // MARK: - 辅助

    /// 执行结果写成新对话，标题带日期，方便在列表里翻回去看。
    private static func makeConversation(for task: ScheduledTask, context: ModelContext) -> Conversation {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        let title = "\(task.title) · \(formatter.string(from: Date()))"

        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.title == title })
        if let existing = (try? context.fetch(descriptor))?.first {
            for message in existing.messages { context.delete(message) }
            existing.agentName = task.agentName
            return existing
        }

        let conversation = Conversation(
            title: title,
            thinkingMode: task.thinkingMode,
            modelID: resolvedModelID()
        )
        conversation.agentName = task.agentName
        context.insert(conversation)
        return conversation
    }

    private static func fetchAgent(named name: String, context: ModelContext) -> AgentDockItem? {
        guard !name.isEmpty else { return nil }
        let descriptor = FetchDescriptor<AgentDockItem>(predicate: #Predicate { $0.name == name })
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchSkill(named name: String, context: ModelContext) -> Skill? {
        guard !name.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Skill>(predicate: #Predicate { $0.name == name })
        return (try? context.fetch(descriptor))?.first
    }

    private static func resolvedModelID() -> String {
        let stored = AppSettings().credential.modelID
        return stored.isEmpty ? "deepseek-chat" : stored
    }

    /// 最近一次将要触发的任务时间，用来安排后台唤醒。
    static func nextFireDate(tasks: [ScheduledTask], after date: Date = Date()) -> Date? {
        tasks.compactMap { $0.nextFireDate(after: date) }.min()
    }
}

import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

/// MCP 服务器的不可变快照：流式任务里只用它，避免跨隔离域传引用类型。
struct MCPServerSnapshot: Sendable, Equatable {
    var id: UUID
    var name: String
    var allowsDataUpload: Bool
    var isEnabled: Bool
    var toolNames: [String]
}

/// 对话状态与流式响应处理。
///
/// 负责：组装请求（系统提示词 + 历史 + 记忆上下文）、消费流式事件、
/// 原地更新助手消息、停止 / 重新生成、长对话摘要与用量统计。
@MainActor
@Observable
final class ChatViewModel {

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var lastPersistAt = Date.distantPast

    // MARK: - 可观察状态

    var conversation: Conversation?
    var inputText: String = ""
    var isGenerating: Bool = false
    var streamingMessageID: UUID?
    var errorMessage: String?
    var waitingForNetwork: Bool = false
    var attachedImages: [Data] = []
    var quotedMessage: ChatMessage?
    var activeAgent: AgentDockItem?
    var activeSkill: Skill?
    var replySuggestions: [String] = []
    var skills: [Skill] = []
    var mcpConfigs: [MCPServerConfig] = []
    /// 斜杠命令上下文：非 nil 表示技能选择器应当展开。
    var slashQuery: String?
    var slashRange: Range<String.Index>?
    var highlightedSkillIndex: Int = 0
    var skillSuggestions: [Skill] = []
    var recommendationConfidence: Double?
    var recommendationReason: String?

    var thinkingMode: ThinkingMode = .thinking {
        didSet {
            conversation?.thinkingMode = thinkingMode
        }
    }

    var resolvedParameters: ModelParameters {
        settings.parameters.applying(thinkingMode)
    }

    @ObservationIgnored private let recommender = IntentRecommender()
    @ObservationIgnored private var recommendTask: Task<Void, Never>?

    // MARK: - 斜杠命令与推荐

    var isSkillPickerVisible: Bool { slashQuery != nil }

    var filteredSkills: [Skill] {
        let query = (slashQuery ?? "").trimmingCharacters(in: .whitespaces)
        let enabled = skills.filter(\.isEnabled)
        guard !query.isEmpty else { return enabled }
        return enabled.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.slashCommand.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    /// 输入变化时调用：维护斜杠上下文 + 触发技能推荐。
    func handleInputChange(_ text: String) {
        if let context = SlashCommand.pickerContext(in: text) {
            if slashQuery == nil { highlightedSkillIndex = 0 }
            slashQuery = context.query
            slashRange = context.slashRange
            skillSuggestions = []
            recommendationConfidence = nil
        } else {
            slashQuery = nil
            slashRange = nil
        }
        scheduleRecommendation(for: text)
    }

    func handleKeyCommand(_ command: InputKeyCommand) -> Bool {
        guard isSkillPickerVisible else { return false }
        let list = filteredSkills
        switch command {
        case .moveUp:
            guard !list.isEmpty else { return true }
            highlightedSkillIndex = (highlightedSkillIndex - 1 + list.count) % list.count
            Haptics.selectionChanged()
            return true
        case .moveDown:
            guard !list.isEmpty else { return true }
            highlightedSkillIndex = (highlightedSkillIndex + 1) % list.count
            Haptics.selectionChanged()
            return true
        case .confirm:
            guard !list.isEmpty else { return true }
            applySkill(list[min(highlightedSkillIndex, list.count - 1)])
            return true
        case .escape:
            dismissSkillPicker(removingCommand: true)
            return true
        }
    }

    func applySkill(_ skill: Skill) {
        if let range = slashRange {
            inputText = SlashCommand.apply(skill: skill, to: inputText, replacing: range)
        } else {
            inputText += "/\(skill.slashCommand) "
        }
        activeSkill = skill
        slashQuery = nil
        slashRange = nil
        highlightedSkillIndex = 0
        Haptics.impact(.light)
    }

    func dismissSkillPicker(removingCommand: Bool) {
        if removingCommand, let range = slashRange {
            inputText = SlashCommand.removingCommand(from: inputText, range: range)
        }
        slashQuery = nil
        slashRange = nil
        highlightedSkillIndex = 0
    }

    func dismissRecommendations() {
        recommendTask?.cancel()
        withAnimation(AppAnimation.recommend) {
            skillSuggestions = []
            replySuggestions = []
            recommendationConfidence = nil
            recommendationReason = nil
        }
    }

    private func scheduleRecommendation(for text: String) {
        recommendTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.suggestionsEnabled, trimmed.count >= 4, !skills.isEmpty else {
            if !skillSuggestions.isEmpty {
                withAnimation(AppAnimation.recommend) { skillSuggestions = [] }
            }
            return
        }

        recommendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            guard let result = await self.recommender.recommend(for: trimmed, skills: self.skills) else {
                withAnimation(AppAnimation.recommend) {
                    self.skillSuggestions = []
                    self.recommendationConfidence = nil
                }
                return
            }
            guard !Task.isCancelled else { return }
            guard let skill = self.skills.first(where: { $0.name == result.skillName }) else { return }
            withAnimation(AppAnimation.recommend) {
                self.skillSuggestions = [skill]
                self.recommendationConfidence = result.confidence
                self.recommendationReason = result.reason
            }
        }
    }

    init(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
    }

    // MARK: - 会话绑定

    func attach(to conversation: Conversation) {
        guard self.conversation?.id != conversation.id else { return }
        stopGenerating(markInterrupted: false)
        self.conversation = conversation
        self.thinkingMode = conversation.thinkingMode
        self.inputText = conversation.draft
        self.quotedMessage = nil
        self.attachedImages = []
        self.errorMessage = nil
    }

    var messages: [ChatMessage] {
        conversation?.orderedMessages ?? []
    }

    var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachedImages.isEmpty) && !isGenerating
    }

    // MARK: - 发送

    func send() {
        guard let conversation, canSend else { return }
        guard settings.hasUsableCredential else {
            errorMessage = LLMError.missingCredential.errorDescription
            return
        }

        let rawText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 文本里带 /命令 时，命令部分不发给模型，只保留正文。
        let resolution = SlashCommand.resolve(text: rawText, skills: skills)
        let text = resolution.skill == nil ? rawText : resolution.body
        if let resolvedSkill = resolution.skill {
            activeSkill = resolvedSkill
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty else {
            return
        }
        let userMessage = ChatMessage(
            role: .user,
            text: text,
            orderIndex: conversation.nextOrderIndex,
            thinkingMode: thinkingMode
        )
        if let image = attachedImages.first {
            userMessage.attachmentData = image
            userMessage.attachmentKind = "image"
        }
        if let quoted = quotedMessage {
            userMessage.quotedMessageID = quoted.id
            userMessage.quotedPreview = String(quoted.text.prefix(80))
        }
        userMessage.agentName = activeAgent?.name ?? ""
        userMessage.skillName = activeSkill?.name ?? ""

        modelContext.insert(userMessage)
        userMessage.conversation = conversation

        conversation.draft = ""
        conversation.updatedAt = Date()
        conversation.regenerateTitleIfNeeded()

        inputText = ""
        attachedImages = []
        quotedMessage = nil
        errorMessage = nil
        replySuggestions = []
        dismissRecommendations()

        persist(force: true)
        beginStreaming(in: conversation)
    }

    /// 重新生成最后一条助手回复。
    func regenerateLast() {
        guard let conversation, !isGenerating else { return }
        let ordered = conversation.orderedMessages
        guard let lastAssistant = ordered.last(where: { $0.role == .assistant }) else { return }
        guard ordered.last?.id == lastAssistant.id else { return }

        modelContext.delete(lastAssistant)
        persist(force: true)
        beginStreaming(in: conversation)
    }

    /// 以指定文本重跑（编辑后重发）。
    func resend(editing message: ChatMessage, newText: String) {
        guard message.role == .user, let conversation else { return }
        message.text = newText
        let ordered = conversation.orderedMessages
        if let index = ordered.firstIndex(where: { $0.id == message.id }) {
            for trailing in ordered[(index + 1)...] {
                modelContext.delete(trailing)
            }
        }
        message.createdAt = Date()
        persist(force: true)
        beginStreaming(in: conversation)
    }

    func delete(message: ChatMessage) {
        modelContext.delete(message)
        persist(force: true)
    }

    func suggestRegeneration(for text: String) {
        guard let conversation else { return }
        inputText = text
        _ = conversation
    }

    // MARK: - 流式生成

    private func beginStreaming(in conversation: Conversation) {
        let assistant = ChatMessage(
            role: .assistant,
            text: "",
            orderIndex: conversation.nextOrderIndex,
            thinkingMode: thinkingMode
        )
        assistant.isStreaming = true
        assistant.agentName = activeAgent?.name ?? ""
        assistant.skillName = activeSkill?.name ?? ""
        modelContext.insert(assistant)
        assistant.conversation = conversation

        isGenerating = true
        streamingMessageID = assistant.id
        waitingForNetwork = false

        if settings.liveActivitiesEnabled {
            ChatActivityManager.start(
                conversationID: conversation.id.uuidString,
                title: conversation.title,
                status: "正在生成",
                preview: "",
                enabled: true
            )
        }

        let credential = settings.resolvedCredential
        var parameters = settings.parameters.applying(thinkingMode)
        parameters.modelID = conversation.modelID
        parameters.streamsResponse = true
        let client = LLMClientFactory.make(for: credential)

        // 记录本条回答引用到的记忆，供气泡上的标签跳转。
        let query = conversation.orderedMessages.last(where: { $0.role == .user })?.text ?? ""
        let hits = settings.memoryEnabled && !query.isEmpty
            ? MemoryStore.shared.search(query, limit: 4)
            : []
        assistant.memoryHitIDs = hits.map(\.id)

        // 只有明确授权上传数据的 MCP 工具才会暴露给云端模型。
        let availableTools = SystemToolRegistry.definitions + MCPToolAdapter.definitions(
            from: MCPClientManager.shared.allTools(configs: mcpConfigs).filter(\.allowsDataUpload)
        )
        // 流式任务里只使用不可变的纯值快照，避免跨隔离域传递持久化对象。
        let serverSnapshots: [MCPServerSnapshot] = mcpConfigs.map { config in
            MCPServerSnapshot(
                id: config.id,
                name: config.displayName,
                allowsDataUpload: config.allowsDataUpload,
                isEnabled: config.isEnabled,
                toolNames: (MCPClientManager.shared.toolsByServer[config.id] ?? []).map(\.name)
            )
        }

        streamTask = Task { [weak self] in
            var accumulated = ""
            var reasoning = ""
            var failure: String?
            var wasInterrupted = false
            guard let self else { return }
            var workingMessages = await self.buildPayloadWithImages(for: conversation)
            var round = 0
            let maximumRounds = 4

            while round < maximumRounds {
                round += 1
                var pendingToolCalls: [LLMToolCall] = []
                var roundText = ""

                do {
                    let stream = client.streamChat(
                        messages: workingMessages,
                        parameters: parameters,
                        credential: credential,
                        tools: availableTools
                    )
                    for try await event in stream {
                        if Task.isCancelled {
                            wasInterrupted = true
                            break
                        }
                        switch event {
                        case .textDelta(let chunk):
                            roundText += chunk
                            accumulated += chunk
                            assistant.text = accumulated
                        case .reasoningDelta(let chunk):
                            reasoning += chunk
                            assistant.thinkingText = reasoning
                        case .usage(let usage):
                            assistant.usage = assistant.usage + usage
                        case .toolCallDelta, .finished:
                            break
                        case .toolCallsReady(let calls):
                            pendingToolCalls = calls
                        }
                        self.persistThrottled()
                    }
                } catch let error as LLMError {
                    if case .cancelled = error {
                        wasInterrupted = true
                    } else {
                        failure = error.errorDescription
                    }
                } catch {
                    failure = error.localizedDescription
                }

                if wasInterrupted || failure != nil { break }
                guard !pendingToolCalls.isEmpty else { break }

                // 把这一轮的文本与工具调用写回上下文，再依次执行工具。
                workingMessages.append(
                    LLMChatMessage(role: .assistant, text: roundText, toolCalls: pendingToolCalls)
                )

                for call in pendingToolCalls {
                    let toolText: String
                    if SystemToolRegistry.isLocalTool(call.name) {
                        toolText = await SystemToolRegistry.invoke(
                            name: call.name,
                            argumentsJSON: call.argumentsJSON,
                            attachedImageData: conversation.orderedMessages
                                .last(where: { $0.role == .user })?
                                .attachmentData
                        )
                    } else {
                        let preferred = serverSnapshots.first { snapshot in
                            snapshot.isEnabled && snapshot.allowsDataUpload && snapshot.toolNames.contains(call.name)
                        } ?? serverSnapshots.first { $0.toolNames.contains(call.name) }

                        let result = await MCPClientManager.shared.callTool(
                            serverID: preferred?.id ?? UUID(),
                            toolName: call.name,
                            argumentsJSON: call.argumentsJSON,
                            serverName: preferred?.name ?? "MCP"
                        )
                        toolText = result.isError ? "工具返回错误：\(result.text)" : result.text
                    }
                    workingMessages.append(
                        LLMChatMessage(
                            role: .tool,
                            text: toolText,
                            toolCallID: call.id,
                            toolName: call.name
                        )
                    )
                }
            }

            assistant.isStreaming = false
            assistant.isInterrupted = wasInterrupted
            if let failure, accumulated.isEmpty {
                assistant.isError = true
                assistant.errorText = failure
                self.errorMessage = failure
            } else if accumulated.isEmpty && !wasInterrupted {
                assistant.isError = true
                assistant.errorText = LLMError.emptyResponse.errorDescription ?? "模型没有返回内容。"
                self.errorMessage = assistant.errorText
            }
            conversation.updatedAt = Date()
            self.isGenerating = false
            self.streamingMessageID = nil
            self.streamTask = nil
            self.persist(force: true)
            if self.settings.liveActivitiesEnabled {
                ChatActivityManager.end(
                    status: wasInterrupted ? "已停止生成" : "回答完成",
                    preview: accumulated
                )
            }
            self.runPostProcessing(for: conversation, credential: credential, parameters: parameters)
        }
    }

    /// 生成结束后的后台收尾：记忆整理、长对话摘要、端侧建议回复。
    private func runPostProcessing(
        for conversation: Conversation,
        credential: APICredential,
        parameters: ModelParameters
    ) {
        Task { [weak self] in
            guard let self else { return }

            if self.settings.memoryEnabled && self.settings.backgroundMemoryReview {
                _ = await MemoryExtractor.review(
                    conversation: conversation,
                    context: self.modelContext,
                    store: MemoryStore.shared
                )
            }

            if self.settings.autoSummarizeEnabled,
               ConversationSummarizer.shouldSummarize(conversation) {
                let summarized = await ConversationSummarizer.summarize(
                    conversation: conversation,
                    credential: credential,
                    parameters: parameters
                )
                if summarized {
                    self.modelContextSave()
                }
            }

            if self.settings.suggestionsEnabled {
                let excerpt = conversation.orderedMessages.suffix(6)
                    .map { ($0.role == .user ? "用户：" : "助手：") + String($0.text.prefix(200)) }
                    .joined(separator: "\n")
                let replies = await OnDeviceLanguageModel.suggestedReplies(for: excerpt)
                if !replies.isEmpty {
                    withAnimation(AppAnimation.recommend) {
                        self.replySuggestions = replies
                    }
                }
            }
        }
    }

    private func modelContextSave() {
        try? modelContext.save()
    }

    func stopGenerating(markInterrupted: Bool = true) {
        guard let task = streamTask else { return }
        task.cancel()
        streamTask = nil
        isGenerating = false
        if let id = streamingMessageID,
           let message = conversation?.orderedMessages.first(where: { $0.id == id }) {
            message.isStreaming = false
            message.isInterrupted = markInterrupted
        }
        streamingMessageID = nil
        persist(force: true)
    }

    // MARK: - 请求组装

    private func buildPayload(for conversation: Conversation) -> [LLMChatMessage] {
        var payload: [LLMChatMessage] = []
        let systemText = buildSystemPrompt(for: conversation)
        if !systemText.isEmpty {
            payload.append(LLMChatMessage(role: .system, text: systemText))
        }

        let ordered = conversation.orderedMessages.filter { !$0.isStreaming }
        for message in ordered {
            switch message.role {
            case .user:
                var images: [Data] = []
                if let data = message.attachmentData { images = [data] }
                payload.append(LLMChatMessage(role: .user, text: message.text, images: images))
            case .assistant:
                guard !message.text.isEmpty else { continue }
                payload.append(LLMChatMessage(role: .assistant, text: message.text))
            case .system, .tool:
                continue
            }
        }
        return payload
    }

    /// 构造请求上下文；带图片的消息会先在本机做一次视觉预处理，
    /// 把 OCR / 条码结果作为附加上下文一起送出，并压缩图片体积。
    private func buildPayloadWithImages(for conversation: Conversation) async -> [LLMChatMessage] {
        var payload: [LLMChatMessage] = []
        let systemText = buildSystemPrompt(for: conversation)
        if !systemText.isEmpty {
            payload.append(LLMChatMessage(role: .system, text: systemText))
        }

        let ordered = conversation.orderedMessages.filter { !$0.isStreaming }
        for message in ordered {
            switch message.role {
            case .user:
                var text = message.text
                var images: [Data] = []

                if let data = message.attachmentData {
                    var caption = message.attachmentCaption
                    if caption.isEmpty {
                        let analysis = await ImageAnalyzer.analyze(data)
                        caption = analysis.summaryForModel
                        message.attachmentCaption = caption
                    }
                    if !caption.isEmpty {
                        text += "\n\n[本机图像分析]\n\(caption)"
                    }
                    images = [ImageAnalyzer.compress(data)]
                }

                payload.append(LLMChatMessage(role: .user, text: text, images: images))

            case .assistant:
                guard !message.text.isEmpty else { continue }
                payload.append(LLMChatMessage(role: .assistant, text: message.text))

            case .system, .tool:
                continue
            }
        }
        return payload
    }

    private func buildSystemPrompt(for conversation: Conversation) -> String {
        var sections: [String] = []

        let base = conversation.systemPromptOverride.isEmpty
            ? settings.parameters.systemPrompt
            : conversation.systemPromptOverride
        if !base.isEmpty { sections.append(base) }

        if let agent = activeAgent, !agent.systemPrompt.isEmpty {
            sections.append("当前智能体：\(agent.name)\n\(agent.systemPrompt)")
        }

        if let skill = activeSkill, !skill.promptPrefix.isEmpty {
            sections.append("当前技能：\(skill.name)\n\(skill.promptPrefix)")
        }

        if !conversation.rollingSummary.isEmpty {
            sections.append("""
            以下是这段对话在此之前的摘要（原文已省略），请把它当作已知背景：
            \(conversation.rollingSummary)
            """)
        }

        if settings.memoryEnabled {
            let memories = relevantMemories(for: conversation)
            if !memories.isEmpty {
                sections.append("""
                以下是用户在本机保存的相关记忆，可作为背景参考，不要主动复述：
                \(memories.map { "- \($0)" }.joined(separator: "\n"))
                """)
            }
        }

        sections.append(Self.timeContext())
        return sections.joined(separator: "\n\n")
    }

    /// 记忆上下文。批 B 接入常驻内存的向量索引后由 MemoryStore 提供。
    private func relevantMemories(for conversation: Conversation) -> [String] {
        guard settings.memoryEnabled else { return [] }
        let query = conversation.orderedMessages
            .last(where: { $0.role == .user })?
            .text ?? ""
        guard !query.isEmpty else { return [] }
        return MemoryStore.shared.contextSnippets(for: query)
    }

    private static func timeContext() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日 EEEE HH:mm"
        let zone = TimeZone.current.identifier
        return "当前本地时间：\(formatter.string(from: Date()))（时区 \(zone)）。涉及相对时间时以这个时间为基准。"
    }

    // MARK: - 持久化

    private func persistThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastPersistAt) > 0.4 else { return }
        lastPersistAt = now
        try? modelContext.save()
        if settings.liveActivitiesEnabled,
           let id = streamingMessageID,
           let message = conversation?.orderedMessages.first(where: { $0.id == id }) {
            ChatActivityManager.update(
                status: "正在生成",
                preview: message.text,
                isGenerating: true,
                tokenCount: message.usage.total
            )
        }
    }

    private func persist(force: Bool) {
        guard force || modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            errorMessage = "本地保存失败：\(error.localizedDescription)"
        }
    }

}

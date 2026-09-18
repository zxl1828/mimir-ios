import Foundation
import Observation
import SwiftData

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
    var suggestedReplies: [String] = []
    var thinkingMode: ThinkingMode = .thinking {
        didSet {
            conversation?.thinkingMode = thinkingMode
        }
    }

    var resolvedParameters: ModelParameters {
        settings.parameters.applying(thinkingMode)
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

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        suggestedReplies = []

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

        let payload = buildPayload(for: conversation)
        let credential = settings.resolvedCredential
        var parameters = settings.parameters.applying(thinkingMode)
        parameters.modelID = conversation.modelID
        parameters.streamsResponse = true
        let client = LLMClientFactory.make(for: credential)

        streamTask = Task { [weak self] in
            var accumulated = ""
            var reasoning = ""
            var failure: String?
            var wasInterrupted = false

            do {
                let stream = client.streamChat(
                    messages: payload,
                    parameters: parameters,
                    credential: credential,
                    tools: []
                )
                for try await event in stream {
                    if Task.isCancelled {
                        wasInterrupted = true
                        break
                    }
                    switch event {
                    case .textDelta(let chunk):
                        accumulated += chunk
                        assistant.text = accumulated
                    case .reasoningDelta(let chunk):
                        reasoning += chunk
                        assistant.thinkingText = reasoning
                    case .usage(let usage):
                        assistant.usage = assistant.usage + usage
                    case .toolCallDelta, .toolCallsReady:
                        break
                    case .finished:
                        break
                    }
                    self?.persistThrottled()
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

            guard let self else { return }
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
        }
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
        []
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

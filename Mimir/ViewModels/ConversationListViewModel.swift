import Foundation
import Observation
import SwiftData

/// 会话列表：新建、切换、删除、重命名、置顶、搜索、按策略自动清理。
@MainActor
@Observable
final class ConversationListViewModel {

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let settings: AppSettings

    var searchText: String = ""
    var conversations: [Conversation] = []

    init(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
    }

    var filteredConversations: [Conversation] {
        // 空会话一律不进列表：点「新建会话」只是打开一张空白的纸，
        // 用户真正发出第一条消息之后它才算一条历史记录。
        let visible = conversations.filter { !$0.messages.isEmpty || $0.isPinned }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return visible }
        return visible.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(keyword)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(keyword) }
        }
    }

    var pinnedConversations: [Conversation] {
        filteredConversations.filter(\.isPinned)
    }

    var regularConversations: [Conversation] {
        filteredConversations.filter { !$0.isPinned }
    }

    func refresh() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
        )
        conversations = (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createConversation() -> Conversation {
        // 复用已存在的空会话，避免连点「新建会话」堆出一串「新对话 · 空会话」。
        if let blank = conversations.first(where: { $0.messages.isEmpty && !$0.isPinned }) {
            return blank
        }
        let modelID = settings.credential.modelID.isEmpty
            ? settings.credential.format.defaultModelID
            : settings.credential.modelID
        let conversation = Conversation(thinkingMode: .thinking, modelID: modelID)
        if !settings.selectedAgentName.isEmpty {
            conversation.agentName = settings.selectedAgentName
        }
        modelContext.insert(conversation)
        save()
        refresh()
        return conversation
    }

    /// 清掉一天以上没有任何消息的空会话（例如点了新建却没输入就退出）。
    func pruneEmptyConversations(olderThan interval: TimeInterval = 24 * 60 * 60) {
        let cutoff = Date().addingTimeInterval(-interval)
        let stale = conversations.filter { $0.messages.isEmpty && !$0.isPinned && $0.updatedAt < cutoff }
        guard !stale.isEmpty else { return }
        for conversation in stale {
            modelContext.delete(conversation)
        }
        save()
        refresh()
    }

    func delete(_ conversation: Conversation) {
        modelContext.delete(conversation)
        save()
        refresh()
    }

    func delete(atOffsets offsets: IndexSet, in list: [Conversation]) {
        for index in offsets {
            guard list.indices.contains(index) else { continue }
            modelContext.delete(list[index])
        }
        save()
        refresh()
    }

    func rename(_ conversation: Conversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.title = trimmed.isEmpty ? "未命名对话" : trimmed
        conversation.updatedAt = Date()
        save()
        refresh()
    }

    func togglePin(_ conversation: Conversation) {
        conversation.isPinned.toggle()
        save()
        refresh()
    }

    func duplicate(_ conversation: Conversation) {
        let copy = Conversation(
            title: conversation.title + " 副本",
            thinkingMode: conversation.thinkingMode,
            modelID: conversation.modelID
        )
        copy.agentName = conversation.agentName
        copy.agentPrompt = conversation.agentPrompt
        copy.rollingSummary = conversation.rollingSummary
        copy.thinkingMode = conversation.thinkingMode
        modelContext.insert(copy)
        for message in conversation.orderedMessages {
            let clone = ChatMessage(
                role: message.role,
                text: message.text,
                createdAt: message.createdAt,
                orderIndex: message.orderIndex,
                thinkingMode: message.thinkingMode
            )
            clone.thinkingText = message.thinkingText
            clone.agentName = message.agentName
            clone.skillName = message.skillName
            clone.attachmentData = message.attachmentData
            clone.attachmentKind = message.attachmentKind
            clone.attachmentCaption = message.attachmentCaption
            clone.promptTokens = message.promptTokens
            clone.completionTokens = message.completionTokens
            clone.reasoningTokens = message.reasoningTokens
            clone.modelID = message.modelID
            clone.priceCostUSD = message.priceCostUSD
            modelContext.insert(clone)
            clone.conversation = copy
        }
        save()
        refresh()
    }

    func markUsed(_ conversation: Conversation) {
        conversation.updatedAt = Date()
        save()
        refresh()
    }

    /// 按 30 天 / 1 年 / 永久 的保留策略清理。
    @discardableResult
    func applyRetentionPolicy() -> Int {
        guard let cutoff = settings.retention.cutoff else { return 0 }
        var removed = 0
        for conversation in conversations where !conversation.isPinned {
            guard conversation.usesAutoDelete else { continue }
            if conversation.updatedAt < cutoff {
                modelContext.delete(conversation)
                removed += 1
            }
        }
        if removed > 0 {
            save()
            refresh()
        }
        return removed
    }

    private func save() {
        try? modelContext.save()
    }
}

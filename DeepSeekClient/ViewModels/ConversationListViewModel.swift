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
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return conversations }
        return conversations.filter { conversation in
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

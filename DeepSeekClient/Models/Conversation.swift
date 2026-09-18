import Foundation
import SwiftData

/// 一段多轮对话。
@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = "新对话"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var isArchived: Bool = false
    var thinkingModeRaw: String = ThinkingMode.thinking.rawValue
    var modelID: String = "deepseek-chat"
    /// 长对话超窗时生成的滚动摘要，替代粗暴截断。
    var rollingSummary: String = ""
    var summarizedUpToIndex: Int = -1
    /// 会话级系统提示词覆盖（为空则用全局）。
    var systemPromptOverride: String = ""
    /// 当前会话使用的智能体（Agent Dock）。
    var agentName: String = ""
    var agentPrompt: String = ""
    var draft: String = ""
    var usesAutoDelete: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = Date(),
        thinkingMode: ThinkingMode = .thinking,
        modelID: String = "deepseek-chat"
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.thinkingModeRaw = thinkingMode.rawValue
        self.modelID = modelID
    }
}

extension Conversation {
    var thinkingMode: ThinkingMode {
        get { ThinkingMode(rawValue: thinkingModeRaw) ?? .thinking }
        set { thinkingModeRaw = newValue.rawValue }
    }

    var orderedMessages: [ChatMessage] {
        messages.sorted { lhs, rhs in
            if lhs.orderIndex == rhs.orderIndex { return lhs.createdAt < rhs.createdAt }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    var lastMessage: ChatMessage? { orderedMessages.last }

    var nextOrderIndex: Int { (messages.map(\.orderIndex).max() ?? -1) + 1 }

    var preview: String {
        guard let last = lastMessage else { return "还没有消息" }
        let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return last.isStreaming ? "正在生成…" : "（空消息）" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    var totalUsage: TokenUsage {
        messages.reduce(TokenUsage.zero) { $0 + $1.usage }
    }

    /// 会话是否已经有内容（用于决定是否复用空白会话）。
    var isEmpty: Bool {
        messages.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 依据首条用户消息自动取标题。
    func regenerateTitleIfNeeded() {
        guard title == "新对话" || title.isEmpty else { return }
        guard let firstUser = orderedMessages.first(where: { $0.role == .user }) else { return }
        let cleaned = firstUser.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !cleaned.isEmpty else { return }
        title = String(cleaned.prefix(24))
    }
}

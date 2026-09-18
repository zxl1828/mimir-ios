import Foundation
import SwiftData

/// 一条端侧记忆。向量索引常驻内存，原始数据仅保存在本机。
@Model
final class MemoryEntry {
    var id: UUID = UUID()
    var text: String = ""
    /// AI 生成的简明摘要（记忆浏览器主列表展示）。
    var summary: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0
    /// 来源溯源。
    var sourceConversationID: UUID?
    var sourceConversationTitle: String = ""
    var sourceMessageID: UUID?
    var sourceQuote: String = ""
    var tags: [String] = []
    /// 标记后不随对话发送到云端 API。
    var localOnly: Bool = false
    var importance: Double = 0.5
    var isUserEdited: Bool = false
    var isAutoExtracted: Bool = true
    /// 端侧嵌入向量（NLEmbedding）。
    var embedding: [Float] = []
    var embeddingVersion: Int = 1

    init(
        id: UUID = UUID(),
        text: String,
        summary: String = "",
        sourceConversationID: UUID? = nil,
        sourceConversationTitle: String = "",
        sourceMessageID: UUID? = nil,
        sourceQuote: String = "",
        tags: [String] = [],
        localOnly: Bool = false,
        importance: Double = 0.5,
        isAutoExtracted: Bool = true
    ) {
        self.id = id
        self.text = text
        self.summary = summary
        self.sourceConversationID = sourceConversationID
        self.sourceConversationTitle = sourceConversationTitle
        self.sourceMessageID = sourceMessageID
        self.sourceQuote = sourceQuote
        self.tags = tags
        self.localOnly = localOnly
        self.importance = importance
        self.isAutoExtracted = isAutoExtracted
    }
}

extension MemoryEntry {
    var displaySummary: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return String(text.prefix(80))
    }

    var sourceLabel: String {
        let trimmed = sourceConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知来源" : trimmed
    }
}

/// 一次检索命中（含本地打分明细，用于“为什么命中”的透明度展示）。
struct MemorySearchHit: Identifiable, Sendable, Equatable {
    var id: UUID
    var text: String
    var score: Float
    var localOnly: Bool
    var sourceConversationTitle: String
}

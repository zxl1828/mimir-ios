import Foundation
import ActivityKit

/// 对话实时活动的共享数据结构（App 与小组件扩展共用）。
struct ChatActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var conversationTitle: String
        var statusText: String
        var previewText: String
        var isGenerating: Bool
        var tokenCount: Int
        var updatedAt: Date

        public init(
            conversationTitle: String,
            statusText: String,
            previewText: String,
            isGenerating: Bool,
            tokenCount: Int,
            updatedAt: Date = Date()
        ) {
            self.conversationTitle = conversationTitle
            self.statusText = statusText
            self.previewText = previewText
            self.isGenerating = isGenerating
            self.tokenCount = tokenCount
            self.updatedAt = updatedAt
        }
    }

    var conversationID: String

    init(conversationID: String) {
        self.conversationID = conversationID
    }
}

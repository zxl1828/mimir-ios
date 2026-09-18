import Foundation
import SwiftData

/// 分支里的一条消息快照。
///
/// 「从这里重新生成」会把后续消息从可见会话里移走，为了能原样切回来，
/// 这里把它们降级成纯值类型保存（SwiftData 模型本身不能跨隔离域传递）。
struct MessageSnapshot: Codable, Sendable {
    var roleRaw: String
    var text: String
    var thinkingText: String
    var createdAt: Date
    var relativeOrder: Int
    var agentName: String
    var skillName: String
    var isInterrupted: Bool
    var attachmentData: Data?
    var attachmentKind: String
    var attachmentCaption: String
    var quotedPreview: String

    init(message: ChatMessage, relativeOrder: Int) {
        self.roleRaw = message.roleRaw
        self.text = message.text
        self.thinkingText = message.thinkingText
        self.createdAt = message.createdAt
        self.relativeOrder = relativeOrder
        self.agentName = message.agentName
        self.skillName = message.skillName
        self.isInterrupted = message.isInterrupted
        self.attachmentData = message.attachmentData
        self.attachmentKind = message.attachmentKind
        self.attachmentCaption = message.attachmentCaption
        self.quotedPreview = message.quotedPreview
    }

    /// 还原成一条真实消息并插入上下文。
    @MainActor
    func makeMessage(
        orderIndex: Int,
        thinkingMode: ThinkingMode,
        context: ModelContext,
        conversation: Conversation
    ) -> ChatMessage {
        let message = ChatMessage(
            role: MessageRole(rawValue: roleRaw) ?? .assistant,
            text: text,
            createdAt: createdAt,
            orderIndex: orderIndex,
            thinkingMode: thinkingMode
        )
        message.thinkingText = thinkingText
        message.agentName = agentName
        message.skillName = skillName
        message.isInterrupted = isInterrupted
        message.attachmentData = attachmentData
        message.attachmentKind = attachmentKind
        message.attachmentCaption = attachmentCaption
        message.quotedPreview = quotedPreview
        context.insert(message)
        message.conversation = conversation
        return message
    }
}

/// 某个回答版本对应的后续消息分支。
struct MessageBranch: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var anchorMessageID: UUID
    var versionIndex: Int
    var createdAt: Date = Date()
    var messages: [MessageSnapshot]
}

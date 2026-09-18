import Foundation
import SwiftData

/// 消息角色。
enum MessageRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
    case tool

    var isFromUser: Bool { self == .user }
}

/// 一条对话消息。
///
/// 使用引用类型以便 SwiftData 持久化并支持流式过程中原地更新
/// （流式渲染时只改 `text`，避免整表重写）。
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var roleRaw: String = MessageRole.user.rawValue
    var text: String = ""
    /// 推理过程单独存放，渲染时折叠显示。
    var thinkingText: String = ""
    var createdAt: Date = Date()
    var isStreaming: Bool = false
    var isInterrupted: Bool = false
    var isError: Bool = false
    var errorText: String = ""
    var thinkingModeRaw: String = ThinkingMode.thinking.rawValue
    /// 本条消息生效的智能体与技能（用于气泡上显示来源标签）。
    var agentName: String = ""
    var skillName: String = ""
    /// 被引用的记忆条目，点击可跳转记忆浏览器。
    var memoryHitIDs: [UUID] = []
    /// 引用的历史消息（“发送后保留选中文本引用”）。
    var quotedMessageID: UUID?
    var quotedPreview: String = ""
    /// 附件（图片），本地保存。
    var attachmentData: Data?
    var attachmentKind: String = ""
    var attachmentCaption: String = ""
    /// 用量统计。
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var reasoningTokens: Int = 0
    var orderIndex: Int = 0

    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        createdAt: Date = Date(),
        orderIndex: Int = 0,
        thinkingMode: ThinkingMode = .thinking
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
        self.orderIndex = orderIndex
        self.thinkingModeRaw = thinkingMode.rawValue
    }
}

extension ChatMessage {
    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var thinkingMode: ThinkingMode {
        get { ThinkingMode(rawValue: thinkingModeRaw) ?? .thinking }
        set { thinkingModeRaw = newValue.rawValue }
    }

    var usage: TokenUsage {
        get {
            TokenUsage(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                reasoningTokens: reasoningTokens
            )
        }
        set {
            promptTokens = newValue.promptTokens
            completionTokens = newValue.completionTokens
            reasoningTokens = newValue.reasoningTokens
        }
    }

    var hasVisibleThinking: Bool {
        !thinkingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAttachment: Bool { attachmentData != nil }

    /// 发送给云端 API 的纯文本内容。
    var apiContent: String { text }

    /// 复制到剪贴板的内容（助手消息带上推理过程更有用）。
    var copyableText: String {
        guard hasVisibleThinking else { return text }
        return """
        【推理过程】
        \(thinkingText)

        【回答】
        \(text)
        """
    }
}

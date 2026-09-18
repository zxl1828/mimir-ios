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

    /// 同一位置的其他回答版本（重新生成产生）。
    /// 索引 0 对应 `text`（原始版本），索引 n 对应 `alternativeBodies[n-1]`。
    var alternativeBodies: [String] = []
    /// 当前显示的版本。0 表示原始 `text`。
    var activeVersionIndex: Int = 0
    /// 流式生成中的临时文本，不落库。
    @Transient var streamingText: String = ""

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

    // MARK: - 版本

    /// 版本总数（含原始版本）。
    var versionCount: Int { 1 + alternativeBodies.count }

    /// 当前应当显示的正文。
    var displayText: String {
        guard activeVersionIndex > 0 else { return text }
        let index = activeVersionIndex - 1
        guard alternativeBodies.indices.contains(index) else { return text }
        return alternativeBodies[index]
    }

    /// 生成过程中实际渲染的内容。
    var renderedText: String {
        isStreaming && !streamingText.isEmpty ? streamingText : displayText
    }

    /// 追加一个空版本并激活它，返回新版本序号。
    @discardableResult
    func beginNewVersion() -> Int {
        alternativeBodies.append("")
        activeVersionIndex = alternativeBodies.count
        streamingText = ""
        return activeVersionIndex
    }

    /// 生成结束时把流式内容写回当前版本。
    func commitStreamingVersion() {
        guard !streamingText.isEmpty else { return }
        if activeVersionIndex > 0, alternativeBodies.indices.contains(activeVersionIndex - 1) {
            alternativeBodies[activeVersionIndex - 1] = streamingText
        } else {
            text = streamingText
        }
        streamingText = ""
    }

    /// 生成失败或被打断时丢弃空的占位版本。
    func discardEmptyVersion() {
        streamingText = ""
        guard activeVersionIndex > 0, alternativeBodies.indices.contains(activeVersionIndex - 1) else { return }
        if alternativeBodies[activeVersionIndex - 1].isEmpty {
            alternativeBodies.remove(at: activeVersionIndex - 1)
            activeVersionIndex = 0
        }
    }

    func switchVersion(to index: Int) {
        activeVersionIndex = min(max(index, 0), versionCount - 1)
    }

    var versionLabel: String {
        "\(min(activeVersionIndex + 1, versionCount))/\(versionCount)"
    }

    /// 发送给云端 API 的纯文本内容。
    var apiContent: String { displayText }

    /// 复制到剪贴板的内容（助手消息带上推理过程更有用）。
    var copyableText: String {
        let body = displayText
        guard hasVisibleThinking else { return body }
        return """
        【推理过程】
        \(thinkingText)

        【回答】
        \(body)
        """
    }
}

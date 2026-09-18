import Foundation
import Observation
import SwiftData

/// 全局搜索范围。
enum GlobalSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case user
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .user: return "我的提问"
        case .assistant: return "助手回答"
        }
    }

    var roleFilter: MessageRole? {
        switch self {
        case .all: return nil
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}

/// 全局搜索的时间范围。
enum GlobalSearchDateFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "全部时间"
        case .week: return "近 7 天"
        case .month: return "近 30 天"
        }
    }

    var cutoff: Date? {
        let calendar = Calendar.current
        switch self {
        case .any: return nil
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
        }
    }
}

/// 命中片段：`isMatch` 为 true 的片段在 UI 里高亮。
struct SearchSnippetSegment: Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let isMatch: Bool

    init(id: UUID = UUID(), text: String, isMatch: Bool) {
        self.id = id
        self.text = text
        self.isMatch = isMatch
    }
}

/// 一条搜索结果。
///
/// 只保存值类型：SwiftData 模型不是 `Sendable`，搜索结果要能安全地
/// 脱离主线程上下文传递，所以这里不持有 `Conversation` / `ChatMessage`。
struct GlobalSearchResult: Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let conversationTitle: String
    let messageID: UUID?
    let role: MessageRole?
    let segments: [SearchSnippetSegment]
    let createdAt: Date
    let matchedInTitle: Bool
    let sourceLabel: String

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        conversationTitle: String,
        messageID: UUID?,
        role: MessageRole?,
        segments: [SearchSnippetSegment],
        createdAt: Date,
        matchedInTitle: Bool,
        sourceLabel: String
    ) {
        self.id = id
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.messageID = messageID
        self.role = role
        self.segments = segments
        self.createdAt = createdAt
        self.matchedInTitle = matchedInTitle
        self.sourceLabel = sourceLabel
    }
}

/// 跨会话全文搜索：标题、正文、推理过程、智能体与技能标签。
///
/// 刻意不使用 SwiftData 的 `#Predicate` 做 `contains`（中文与大小写行为
/// 不稳定），改为在主线程上内存扫描；每个会话只排序一次。
@MainActor
@Observable
final class GlobalSearchViewModel {

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    var query: String = ""
    var scope: GlobalSearchScope = .all
    var dateFilter: GlobalSearchDateFilter = .any
    var results: [GlobalSearchResult] = []
    var isSearching: Bool = false
    var truncated: Bool = false
    var conversationHitCount: Int = 0
    var hitLimit: Int = 300

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 输入变化：250ms 防抖后搜索。
    func updateQuery(_ text: String) {
        query = text
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.performSearch()
        }
    }

    /// 过滤条件变化：立即重搜。
    func searchNow() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.performSearch()
        }
    }

    // MARK: - 搜索

    private func performSearch() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            results = []
            truncated = false
            conversationHitCount = 0
            return
        }

        isSearching = true
        defer { isSearching = false }

        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
        )
        let conversations = (try? modelContext.fetch(descriptor)) ?? []
        let cutoff = dateFilter.cutoff
        let roleFilter = scope.roleFilter

        var titleHits: [GlobalSearchResult] = []
        var messageHits: [GlobalSearchResult] = []
        var hitConversations = Set<UUID>()
        var reachedLimit = false

        for conversation in conversations {
            if reachedLimit { break }
            if let cutoff, conversation.updatedAt < cutoff { continue }

            if conversation.title.localizedCaseInsensitiveContains(keyword) {
                titleHits.append(
                    GlobalSearchResult(
                        conversationID: conversation.id,
                        conversationTitle: conversation.title,
                        messageID: nil,
                        role: nil,
                        segments: Self.makeSegments(in: conversation.title, keyword: keyword),
                        createdAt: conversation.updatedAt,
                        matchedInTitle: true,
                        sourceLabel: "对话标题"
                    )
                )
                hitConversations.insert(conversation.id)
            }

            let ordered = conversation.orderedMessages
            for message in ordered.reversed() {
                if titleHits.count + messageHits.count >= hitLimit {
                    reachedLimit = true
                    break
                }
                if let cutoff, message.createdAt < cutoff { continue }
                if let roleFilter, message.role != roleFilter { continue }
                guard let hit = Self.match(message: message, in: conversation, keyword: keyword) else { continue }
                messageHits.append(hit)
                hitConversations.insert(conversation.id)
            }
        }

        var combined = titleHits + messageHits
        combined.sort { lhs, rhs in
            if lhs.matchedInTitle != rhs.matchedInTitle { return lhs.matchedInTitle }
            return lhs.createdAt > rhs.createdAt
        }
        if combined.count > hitLimit {
            combined = Array(combined.prefix(hitLimit))
            reachedLimit = true
        }

        results = combined
        truncated = reachedLimit
        conversationHitCount = hitConversations.count
    }

    private static func match(
        message: ChatMessage,
        in conversation: Conversation,
        keyword: String
    ) -> GlobalSearchResult? {
        let fields: [(value: String, label: String)] = [
            (message.text, ""),
            (message.thinkingText, "推理过程"),
            (message.agentName, "智能体"),
            (message.skillName, "技能")
        ]

        for field in fields {
            guard !field.value.isEmpty,
                  field.value.localizedCaseInsensitiveContains(keyword) else { continue }
            var segments = makeSegments(in: field.value, keyword: keyword)
            if !field.label.isEmpty {
                segments.insert(SearchSnippetSegment(text: "\(field.label) · ", isMatch: false), at: 0)
            }
            return GlobalSearchResult(
                conversationID: conversation.id,
                conversationTitle: conversation.title,
                messageID: message.id,
                role: message.role,
                segments: segments,
                createdAt: message.createdAt,
                matchedInTitle: false,
                sourceLabel: field.label.isEmpty ? "消息" : field.label
            )
        }
        return nil
    }

    /// 截取命中位置前后一小段文字，并把命中词切成分段交给 UI 上色。
    private static func makeSegments(in rawText: String, keyword: String) -> [SearchSnippetSegment] {
        let text = rawText.replacingOccurrences(of: "\n", with: " ")
        guard !text.isEmpty else { return [] }
        guard !keyword.isEmpty else {
            return [SearchSnippetSegment(text: String(text.prefix(120)), isMatch: false)]
        }
        guard let match = text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return [SearchSnippetSegment(text: String(text.prefix(120)), isMatch: false)]
        }

        let radius = 48
        let start = text.index(match.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end])
        if start != text.startIndex { snippet = "…" + snippet }
        if end != text.endIndex { snippet += "…" }

        var segments: [SearchSnippetSegment] = []
        var cursor = snippet.startIndex
        while let found = snippet.range(
            of: keyword,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: cursor..<snippet.endIndex
        ) {
            if found.lowerBound > cursor {
                segments.append(SearchSnippetSegment(text: String(snippet[cursor..<found.lowerBound]), isMatch: false))
            }
            segments.append(SearchSnippetSegment(text: String(snippet[found.lowerBound..<found.upperBound]), isMatch: true))
            cursor = found.upperBound
        }
        if cursor < snippet.endIndex {
            segments.append(SearchSnippetSegment(text: String(snippet[cursor..<snippet.endIndex]), isMatch: false))
        }
        return segments.isEmpty ? [SearchSnippetSegment(text: snippet, isMatch: false)] : segments
    }
}

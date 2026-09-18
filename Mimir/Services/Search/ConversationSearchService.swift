import Foundation
import Observation
import SwiftData

// MARK: - 搜索范围与筛选

enum GlobalSearchScope: String, CaseIterable, Identifiable {
    case all
    case messages
    case titles
    case memories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .messages: return "消息"
        case .titles: return "标题"
        case .memories: return "记忆"
        }
    }
}

enum GlobalSearchDateFilter: String, CaseIterable, Identifiable {
    case any
    case today
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "不限时间"
        case .today: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "今年"
        }
    }

    /// 命中内容必须晚于这个时间点；不限时间时返回 nil。
    var cutoff: Date? {
        let calendar = Calendar.current
        switch self {
        case .any:
            return nil
        case .today:
            return calendar.startOfDay(for: Date())
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: Date())
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: Date())
        }
    }
}

// MARK: - 结果模型

/// 高亮片段：命中部分与普通部分交替排列，渲染时只给命中段上色。
struct SearchSnippetSegment: Hashable, Sendable {
    var text: String
    var isMatch: Bool
}

struct GlobalSearchResult: Identifiable, Sendable {
    var id: String
    var conversationID: UUID
    var messageID: UUID?
    var conversationTitle: String
    var sourceLabel: String
    var createdAt: Date
    var matchedInTitle: Bool
    var role: MessageRole
    var segments: [SearchSnippetSegment]
    var score: Int
}

// MARK: - 搜索视图模型

/// 跨对话、跨记忆的全文检索。
///
/// 数据全部在本地内存里过一遍：个人使用的数据量下这样比维护索引更简单，
/// 也不会把任何内容送出设备。
@MainActor
@Observable
final class GlobalSearchViewModel {

    @ObservationIgnored private let modelContext: ModelContext

    var query: String = ""
    var scope: GlobalSearchScope = .all
    var dateFilter: GlobalSearchDateFilter = .any
    var results: [GlobalSearchResult] = []
    let hitLimit = 120
    var truncated = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var conversationHitCount: Int {
        Set(results.map(\.conversationID)).count
    }

    func updateQuery(_ text: String) {
        query = text
        searchNow()
    }

    func searchNow() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.count >= 1 else {
            results = []
            truncated = false
            return
        }

        var collected: [GlobalSearchResult] = []
        let cutoff = dateFilter.cutoff

        if scope == .all || scope == .titles || scope == .messages {
            collected.append(contentsOf: searchConversations(keyword: keyword, cutoff: cutoff))
        }
        if scope == .all || scope == .memories {
            collected.append(contentsOf: searchMemories(keyword: keyword, cutoff: cutoff))
        }

        collected.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }

        truncated = collected.count > hitLimit
        results = Array(collected.prefix(hitLimit))
    }

    // MARK: - 对话

    private func searchConversations(keyword: String, cutoff: Date?) -> [GlobalSearchResult] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
        )
        let conversations = (try? modelContext.fetch(descriptor)) ?? []
        var hits: [GlobalSearchResult] = []

        for conversation in conversations {
            let titleMatch = conversation.title.range(of: keyword, options: .caseInsensitive) != nil

            if scope != .memories, titleMatch {
                if let cutoff, conversation.updatedAt < cutoff { continue }
                hits.append(
                    GlobalSearchResult(
                        id: "title-\(conversation.id.uuidString)",
                        conversationID: conversation.id,
                        messageID: nil,
                        conversationTitle: conversation.title,
                        sourceLabel: "标题",
                        createdAt: conversation.updatedAt,
                        matchedInTitle: true,
                        role: .assistant,
                        segments: Self.makeSnippet(text: conversation.title, keyword: keyword),
                        score: 90
                    )
                )
            }

            if scope == .titles { continue }

            for message in conversation.orderedMessages {
                let fields: [(text: String, label: String, bonus: Int, role: MessageRole)] = [
                    (message.displayText, message.role == .user ? "你说" : "回答", 20, message.role),
                    (message.thinkingText, "推理", 6, .assistant),
                    (message.agentName, "智能体", 8, .assistant),
                    (message.skillName, "技能", 8, .assistant)
                ]

                for field in fields {
                    let trimmed = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    guard trimmed.range(of: keyword, options: .caseInsensitive) != nil else { continue }
                    if let cutoff, message.createdAt < cutoff { continue }

                    hits.append(
                        GlobalSearchResult(
                            id: "\(message.id.uuidString)-\(field.label)",
                            conversationID: conversation.id,
                            messageID: message.id,
                            conversationTitle: conversation.title,
                            sourceLabel: field.label,
                            createdAt: message.createdAt,
                            matchedInTitle: false,
                            role: field.role,
                            segments: Self.makeSnippet(text: trimmed, keyword: keyword),
                            score: 40 + field.bonus + (titleMatch ? 6 : 0)
                        )
                    )
                    // 同一条消息只保留一个最相关的字段命中
                    break
                }
            }
        }
        return hits
    }

    // MARK: - 记忆

    private func searchMemories(keyword: String, cutoff: Date?) -> [GlobalSearchResult] {
        let descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\MemoryEntry.updatedAt, order: .reverse)]
        )
        let memories = (try? modelContext.fetch(descriptor)) ?? []
        var hits: [GlobalSearchResult] = []

        for memory in memories {
            let haystacks = [memory.summary, memory.text, memory.sourceConversationTitle]
            guard let matched = haystacks.first(where: {
                $0.range(of: keyword, options: .caseInsensitive) != nil
            }) else { continue }
            if let cutoff, memory.updatedAt < cutoff { continue }

            hits.append(
                GlobalSearchResult(
                    id: "memory-\(memory.id.uuidString)",
                    conversationID: memory.sourceConversationID ?? UUID(),
                    messageID: memory.sourceMessageID,
                    conversationTitle: memory.sourceLabel,
                    sourceLabel: "记忆",
                    createdAt: memory.updatedAt,
                    matchedInTitle: false,
                    role: .assistant,
                    segments: Self.makeSnippet(text: matched, keyword: keyword),
                    score: 60
                )
            )
        }
        return hits
    }

    // MARK: - 摘要片段

    /// 截取命中位置周围的一段文本，并把命中部分标出来。
    static func makeSnippet(
        text: String,
        keyword: String,
        leading: Int = 36,
        trailing: Int = 70
    ) -> [SearchSnippetSegment] {
        let source = text as NSString
        let lowered = text.lowercased() as NSString
        let needle = keyword.lowercased()
        guard needle.isEmpty == false, source.length > 0 else {
            return [SearchSnippetSegment(text: text, isMatch: false)]
        }

        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < source.length, ranges.count < 24 {
            let found = lowered.range(
                of: needle,
                options: [],
                range: NSRange(location: cursor, length: source.length - cursor)
            )
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            cursor = found.location + max(found.length, 1)
        }

        guard let first = ranges.first else {
            return [SearchSnippetSegment(text: String(text.prefix(90)), isMatch: false)]
        }

        let windowStart = max(0, first.location - leading)
        let windowEnd = min(source.length, first.upperBound + trailing)
        let window = NSRange(location: windowStart, length: windowEnd - windowStart)

        var segments: [SearchSnippetSegment] = []
        if windowStart > 0 {
            segments.append(SearchSnippetSegment(text: "…", isMatch: false))
        }

        var position = window.location
        for range in ranges where NSIntersectionRange(range, window).length > 0 {
            if range.location > position {
                segments.append(
                    SearchSnippetSegment(
                        text: source.substring(with: NSRange(location: position, length: range.location - position)),
                        isMatch: false
                    )
                )
            }
            segments.append(SearchSnippetSegment(text: source.substring(with: range), isMatch: true))
            position = range.upperBound
        }
        if position < window.upperBound {
            segments.append(
                SearchSnippetSegment(
                    text: source.substring(with: NSRange(location: position, length: window.upperBound - position)),
                    isMatch: false
                )
            )
        }
        if windowEnd < source.length {
            segments.append(SearchSnippetSegment(text: "…", isMatch: false))
        }

        return segments
    }
}

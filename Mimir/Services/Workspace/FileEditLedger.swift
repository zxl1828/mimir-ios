import Foundation
import Observation

/// 文件编辑台账（`FileEditLedger`）。
///
/// 每一次经由 `WorkspaceManager.writeWorkspaceText` 的真实落盘都会在这里记一条：
/// 哪个文件、加了几行、删了几行。按"当前生成轮次"（助手消息 id）分桶，
/// 于是对话流结尾就能给出「已编辑 X 个文件 · +N / -M」的统计卡片。
///
/// 全部只存在内存里，与 `ToolCallTelemetry` 一样不落盘、不外发。
@MainActor
@Observable
final class FileEditLedger {

    static let shared = FileEditLedger()

    struct Edit: Identifiable, Sendable {
        let id = UUID()
        /// 工作区相对路径（不是绝对路径，避免把用户名、卷名带进 UI）。
        var path: String
        var added: Int
        var removed: Int
        var occurredAt: Date
    }

    /// 每个轮次最多留这么多条文件记录，防止一次批量重构撑爆内存。
    private static let perRunLimit = 120
    /// 最多保留这么多轮。
    private static let runLimit = 40

    private(set) var edits: [UUID: [Edit]] = [:]

    /// 当前正在生成的助手消息 id；为 nil 时落盘不计入任何卡片。
    var activeRunID: UUID?

    private init() {}

    // MARK: - 写入

    func record(path: String, added: Int, removed: Int) {
        guard let runID = activeRunID else { return }
        guard added > 0 || removed > 0 else { return }

        var bucket = edits[runID] ?? []
        if let index = bucket.firstIndex(where: { $0.path == path }) {
            bucket[index].added += added
            bucket[index].removed += removed
            bucket[index].occurredAt = Date()
        } else {
            bucket.append(Edit(path: path, added: added, removed: removed, occurredAt: Date()))
            if bucket.count > Self.perRunLimit {
                bucket.removeFirst(bucket.count - Self.perRunLimit)
            }
        }
        edits[runID] = bucket

        if edits.count > Self.runLimit {
            let overflow = edits.count - Self.runLimit
            for key in edits.keys.prefix(overflow) {
                edits.removeValue(forKey: key)
            }
        }
    }

    // MARK: - 读取

    func edits(for runID: UUID) -> [Edit] {
        edits[runID] ?? []
    }

    func totals(for runID: UUID) -> (files: Int, added: Int, removed: Int) {
        let list = edits(for: runID)
        return (
            list.count,
            list.reduce(0) { $0 + $1.added },
            list.reduce(0) { $0 + $1.removed }
        )
    }

    func hasEdits(for runID: UUID) -> Bool {
        !(edits[runID]?.isEmpty ?? true)
    }

    func clear(runID: UUID) {
        edits.removeValue(forKey: runID)
    }
}

/// 逐行差异统计：只算"加了多少行 / 删了多少行"，不保留内容。
///
/// 用多重集合计数代替完整 LCS：文件最大 2MB，LCS 会在大文件上退化成 O(n·m)，
/// 而卡片只需要两个数字，多重集合的 O(n) 足够准确。
enum LineDiff {

    static func counts(old: String?, new: String) -> (added: Int, removed: Int) {
        let newLines = splitLines(new)
        guard let old else { return (newLines.count, 0) }

        var remaining = splitLines(old)
        var pool: [String: Int] = [:]
        for line in remaining {
            pool[line, default: 0] += 1
        }
        var added = 0
        for line in newLines {
            if let count = pool[line], count > 0 {
                pool[line] = count - 1
            } else {
                added += 1
            }
        }
        var removed = 0
        for (_, count) in pool where count > 0 {
            removed += count
        }
        remaining.removeAll()
        return (added, removed)
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

import Foundation
import Dispatch
import NaturalLanguage
import Accelerate
import SwiftData

/// 端侧记忆索引。
///
/// 设计约束（来自需求）：索引常驻内存、启动时预热、检索不经过文件系统、
/// 目标延迟低于 1 毫秒、数据永不离开设备。
@MainActor
final class MemoryStore {

    static let shared = MemoryStore()

    struct Item: Sendable {
        var id: UUID
        var vector: [Float]
        var norm: Float
        var localOnly: Bool
        var summary: String
        var text: String
        var sourceTitle: String
        var importance: Double
    }

    private(set) var items: [Item] = []
    private(set) var isWarm = false
    private(set) var lastSearchMicros: Int = 0
    private var embedder: NLEmbedding?
    private var pendingEmbeddingIDs: Set<UUID> = []

    private init() {}

    // MARK: - 预热

    /// 启动预热：加载向量、构建内存索引。缺失向量在后台补齐，不阻塞启动。
    func warmUp(context: ModelContext) {
        guard !isWarm else { return }
        embedder = Self.makeEmbedder()

        let descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\MemoryEntry.updatedAt, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []

        var loaded: [Item] = []
        var missing: [MemoryEntry] = []

        for entry in entries {
            if entry.embedding.count == Self.dimension(for: embedder), entry.embeddingVersion == Self.currentVersion {
                loaded.append(Self.makeItem(entry))
            } else {
                missing.append(entry)
            }
        }

        items = loaded
        isWarm = true

        if !missing.isEmpty {
            Task { @MainActor in
                for entry in missing {
                    await backfill(entry: entry, context: context)
                }
            }
        }
    }

    func invalidate() {
        isWarm = false
        items.removeAll()
    }

    // MARK: - 写入

    func upsert(entry: MemoryEntry, context: ModelContext) {
        items.removeAll { $0.id == entry.id }
        guard let vector = embed(entry.text.isEmpty ? entry.summary : entry.text) else { return }
        entry.embedding = vector
        entry.embeddingVersion = Self.currentVersion
        items.append(
            Item(
                id: entry.id,
                vector: vector,
                norm: Self.norm(vector),
                localOnly: entry.localOnly,
                summary: entry.displaySummary,
                text: entry.text,
                sourceTitle: entry.sourceLabel,
                importance: entry.importance
            )
        )
        try? context.save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func rebuild(from entries: [MemoryEntry]) {
        items = entries
            .filter { $0.embedding.count == Self.dimension(for: embedder) }
            .map(Self.makeItem)
    }

    // MARK: - 检索

    /// 在内存中检索最相关的记忆。
    /// - Parameter excludesLocalOnly: 需要把内容发往云端时传 true，跳过仅本地记忆。
    func search(
        _ query: String,
        limit: Int = 4,
        minimumScore: Float = 0.32,
        excludesLocalOnly: Bool = false
    ) -> [MemorySearchHit] {
        guard !items.isEmpty else { return [] }
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            lastSearchMicros = Int(elapsed / 1_000)
        }

        guard let queryVector = embed(query) else { return [] }
        let queryNorm = Self.norm(queryVector)
        guard queryNorm > 0 else { return [] }

        var scored: [(item: Item, score: Float)] = []
        scored.reserveCapacity(items.count)

        for item in items {
            if excludesLocalOnly && item.localOnly { continue }
            guard item.vector.count == queryVector.count else { continue }
            let score = Self.cosine(queryVector, item.vector, queryNorm: queryNorm, itemNorm: item.norm)
            guard score >= minimumScore else { continue }
            // 重要程度作为轻微加成，避免高重要度的长期记忆被淹没。
            scored.append((item, score + Float(item.importance) * 0.04))
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(limit).map { pair in
            MemorySearchHit(
                id: pair.item.id,
                text: pair.item.summary.isEmpty ? pair.item.text : pair.item.summary,
                score: pair.score,
                localOnly: pair.item.localOnly,
                sourceConversationTitle: pair.item.sourceTitle
            )
        }
    }

    /// 供系统提示词使用的上下文片段。
    func contextSnippets(for query: String, limit: Int = 4) -> [String] {
        search(query, limit: limit, excludesLocalOnly: true).map { hit in
            "- \(hit.text)"
        }
    }

    // MARK: - 嵌入

    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let embedder else { return nil }
        let clipped = trimmed.count > 400 ? String(trimmed.prefix(400)) : trimmed
        guard let vector = embedder.vector(for: clipped) else { return nil }
        return vector.map { Float($0) }
    }

    private func backfill(entry: MemoryEntry, context: ModelContext) async {
        guard !pendingEmbeddingIDs.contains(entry.id) else { return }
        pendingEmbeddingIDs.insert(entry.id)
        defer { pendingEmbeddingIDs.remove(entry.id) }

        let source = entry.text.isEmpty ? entry.summary : entry.text
        guard let vector = embed(source) else { return }
        entry.embedding = vector
        entry.embeddingVersion = Self.currentVersion
        try? context.save()
        items.insert(
            Item(
                id: entry.id,
                vector: vector,
                norm: Self.norm(vector),
                localOnly: entry.localOnly,
                summary: entry.displaySummary,
                text: entry.text,
                sourceTitle: entry.sourceLabel,
                importance: entry.importance
            ),
            at: 0
        )
    }

    // MARK: - 工具

    private static func makeEmbedder() -> NLEmbedding? {
        NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
    }

    private static func makeItem(_ entry: MemoryEntry) -> Item {
        Item(
            id: entry.id,
            vector: entry.embedding,
            norm: norm(entry.embedding),
            localOnly: entry.localOnly,
            summary: entry.displaySummary,
            text: entry.text,
            sourceTitle: entry.sourceLabel,
            importance: entry.importance
        )
    }

    static func dimension(for embedder: NLEmbedding?) -> Int {
        embedder?.dimension ?? 512
    }

    static let currentVersion = 1

    private static func norm(_ vector: [Float]) -> Float {
        guard !vector.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_svesq(vector, 1, &sum, vDSP_Length(vector.count))
        return sqrt(sum)
    }

    private static func cosine(_ a: [Float], _ b: [Float], queryNorm: Float, itemNorm: Float) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        let denominator = queryNorm * itemNorm
        return denominator > 0 ? dot / denominator : 0
    }
}

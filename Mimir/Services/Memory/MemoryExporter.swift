import Foundation
import SwiftData

/// 记忆库 / 技能库的导入导出（JSON）。
enum MemoryExporter {

    struct Payload: Codable {
        struct Entry: Codable {
            var id: UUID
            var text: String
            var summary: String
            var createdAt: Date
            var updatedAt: Date
            var tags: [String]
            var localOnly: Bool
            var importance: Double
            var sourceConversationTitle: String
            var sourceQuote: String
        }
        var schemaVersion: Int = 1
        var exportedAt: Date = Date()
        var entries: [Entry]
    }

    /// 导出全部记忆条目到临时文件，返回可分享的地址。
    @MainActor
    static func exportMemories(context: ModelContext) -> URL? {
        let descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\MemoryEntry.createdAt, order: .forward)]
        )
        guard let entries = try? context.fetch(descriptor) else { return nil }

        let payload = Payload(
            entries: entries.map { entry in
                Payload.Entry(
                    id: entry.id,
                    text: entry.text,
                    summary: entry.summary,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt,
                    tags: entry.tags,
                    localOnly: entry.localOnly,
                    importance: entry.importance,
                    sourceConversationTitle: entry.sourceConversationTitle,
                    sourceQuote: entry.sourceQuote
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }

        let name = "mimir-memories-\(Self.stamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 导入记忆条目（按 id 去重）。
    @MainActor
    @discardableResult
    static func importMemories(from url: URL, context: ModelContext) -> Result<Int, Error> {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: data)

            let existing = Set((try? context.fetch(FetchDescriptor<MemoryEntry>()))?.map(\.id) ?? [])
            var imported = 0
            for entry in payload.entries where !existing.contains(entry.id) {
                let model = MemoryEntry(
                    id: entry.id,
                    text: entry.text,
                    summary: entry.summary,
                    sourceConversationTitle: entry.sourceConversationTitle,
                    sourceQuote: entry.sourceQuote,
                    tags: entry.tags,
                    localOnly: entry.localOnly,
                    importance: entry.importance,
                    isAutoExtracted: false
                )
                model.createdAt = entry.createdAt
                model.updatedAt = entry.updatedAt
                context.insert(model)
                imported += 1
            }
            try context.save()
            return .success(imported)
        } catch {
            return .failure(error)
        }
    }

    static func skillDocumentData(for skill: Skill) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(SkillDocument(skill: skill))
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

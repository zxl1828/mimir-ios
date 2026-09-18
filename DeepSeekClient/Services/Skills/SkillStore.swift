import Foundation
import SwiftData

/// 技能的增删改与导入导出。
@MainActor
enum SkillStore {

    static func allSkills(context: ModelContext) -> [Skill] {
        let descriptor = FetchDescriptor<Skill>(sortBy: [SortDescriptor(\Skill.sortIndex)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func enabledSkills(context: ModelContext) -> [Skill] {
        allSkills(context: context).filter(\.isEnabled)
    }

    @discardableResult
    static func create(
        name: String,
        slashCommand: String,
        icon: String,
        summary: String,
        promptPrefix: String,
        triggerKeywords: [String],
        intentLabel: String,
        toolNames: [String],
        context: ModelContext
    ) -> Skill {
        let nextIndex = (allSkills(context: context).map(\.sortIndex).max() ?? -1) + 1
        let skill = Skill(
            name: name,
            slashCommand: slashCommand.isEmpty ? name : slashCommand,
            icon: icon,
            summary: summary,
            promptPrefix: promptPrefix,
            triggerKeywords: triggerKeywords,
            intentLabel: intentLabel,
            isBuiltin: false,
            toolNames: toolNames,
            sortIndex: nextIndex
        )
        context.insert(skill)
        try? context.save()
        return skill
    }

    static func delete(_ skill: Skill, context: ModelContext) {
        guard !skill.isBuiltin else { return }
        context.delete(skill)
        try? context.save()
    }

    static func restoreBuiltins(context: ModelContext) {
        let existing = Set(allSkills(context: context).map(\.name))
        var nextIndex = (allSkills(context: context).map(\.sortIndex).max() ?? -1) + 1
        for seed in Skill.builtinSeeds() where !existing.contains(seed.name) {
            seed.sortIndex = nextIndex
            nextIndex += 1
            context.insert(seed)
        }
        try? context.save()
    }

    // MARK: - 导入 / 导出

    static func exportDocument(for skill: Skill) -> URL? {
        guard let data = MemoryExporter.skillDocumentData(for: skill) else { return nil }
        let safeName = skill.slashCommand.isEmpty ? skill.name : skill.slashCommand
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-\(safeName).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func importDocument(from url: URL, context: ModelContext) -> SkillImportResult {
        do {
            let data = try Data(contentsOf: url)
            let documents = try Self.decodeDocuments(from: data)
            guard !documents.isEmpty else {
                return .failure(reason: "文件里没有可导入的技能。")
            }

            let existingNames = Set(allSkills(context: context).map(\.name))
            var nextIndex = (allSkills(context: context).map(\.sortIndex).max() ?? -1) + 1
            var added = 0

            for document in documents {
                var name = document.name
                if existingNames.contains(name) {
                    name = name + "（导入）"
                }
                let skill = document.makeSkill()
                skill.name = name
                skill.sortIndex = nextIndex
                nextIndex += 1
                context.insert(skill)
                added += 1
            }
            try context.save()
            return .added(count: added)
        } catch {
            return .failure(reason: "无法解析这个文件：\(error.localizedDescription)")
        }
    }

    /// 支持单个技能对象、技能数组、以及带 skills 字段的集合文件。
    private static func decodeDocuments(from data: Data) throws -> [SkillDocument] {
        let decoder = JSONDecoder()

        if let single = try? decoder.decode(SkillDocument.self, from: data) {
            return [single]
        }
        if let list = try? decoder.decode([SkillDocument].self, from: data) {
            return list
        }

        struct Collection: Decodable {
            var skills: [SkillDocument]
        }
        if let collection = try? decoder.decode(Collection.self, from: data) {
            return collection.skills
        }

        throw SkillImportError.unrecognized
    }

    enum SkillImportError: LocalizedError {
        case unrecognized

        var errorDescription: String? {
            "这不是有效的技能文件。"
        }
    }
}

/// 斜杠命令的解析工具。
enum SlashCommand {

    /// 判断当前输入是否应当弹出技能选择器，并给出已输入的命令前缀。
    ///
    /// 触发条件：最后一个 `/` 位于内容开头或空白之后，且其后没有空白。
    static func pickerContext(in text: String) -> (isActive: Bool, query: String, slashRange: Range<String.Index>?)? {
        guard let slashIndex = text.lastIndex(of: "/") else { return nil }

        if slashIndex != text.startIndex {
            let previous = text[text.index(before: slashIndex)]
            guard previous.isWhitespace || previous.isNewline else { return nil }
        }

        let after = text[text.index(after: slashIndex)...]
        guard !after.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }

        return (true, String(after), slashIndex..<text.endIndex)
    }

    /// 用选中的技能替换当前命令片段。
    static func apply(skill: Skill, to text: String, replacing range: Range<String.Index>) -> String {
        var updated = text
        updated.replaceSubrange(range, with: "/\(skill.slashCommand) ")
        return updated
    }

    /// 从输入里移除未完成的斜杠命令（按 Esc 或点外部时使用）。
    static func removingCommand(from text: String, range: Range<String.Index>) -> String {
        var updated = text
        updated.removeSubrange(range)
        return updated
    }

    /// 解析最终发送的文本，返回命中的技能与剥离命令后的正文。
    static func resolve(text: String, skills: [Skill]) -> (skill: Skill?, body: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return (nil, text) }

        let withoutSlash = String(trimmed.dropFirst())
        let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let command = parts.first else { return (nil, text) }

        let matcher = String(command).lowercased()
        guard let skill = skills.first(where: {
            $0.slashCommand.lowercased() == matcher || $0.name.lowercased() == matcher
        }) else {
            return (nil, text)
        }

        let body = parts.count > 1 ? String(parts[1]) : ""
        return (skill, body)
    }
}

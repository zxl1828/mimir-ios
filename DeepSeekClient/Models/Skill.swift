import Foundation
import SwiftData

/// 技能：可复用的提示词前缀 + 触发关键词 + 意图标签。
@Model
final class Skill {
    var id: UUID = UUID()
    /// 显示名称，例如“代码审查”。
    var name: String = ""
    /// 斜杠命令（不含斜杠），用户输入 `/` 后展示。
    var slashCommand: String = ""
    var icon: String = "wand.and.stars"
    var summary: String = ""
    /// 作用在系统提示词前的技能前缀。
    var promptPrefix: String = ""
    /// 关键词匹配用的触发词。
    var triggerKeywords: [String] = []
    /// 意图分类标签（Foundation Models 少样本分类用）。
    var intentLabel: String = ""
    var isBuiltin: Bool = true
    var isEnabled: Bool = true
    var toolNames: [String] = []
    var accentHex: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortIndex: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        slashCommand: String,
        icon: String = "wand.and.stars",
        summary: String = "",
        promptPrefix: String = "",
        triggerKeywords: [String] = [],
        intentLabel: String = "",
        isBuiltin: Bool = true,
        isEnabled: Bool = true,
        toolNames: [String] = [],
        accentHex: String = "",
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.slashCommand = slashCommand
        self.icon = icon
        self.summary = summary
        self.promptPrefix = promptPrefix
        self.triggerKeywords = triggerKeywords
        self.intentLabel = intentLabel
        self.isBuiltin = isBuiltin
        self.isEnabled = isEnabled
        self.toolNames = toolNames
        self.accentHex = accentHex
        self.sortIndex = sortIndex
    }
}

// MARK: - 导入 / 导出

/// 技能的可分享表示（JSON 导入导出用）。
struct SkillDocument: Codable, Sendable, Equatable {
    var schemaVersion: Int = 1
    var name: String
    var slashCommand: String
    var icon: String
    var summary: String
    var promptPrefix: String
    var triggerKeywords: [String]
    var intentLabel: String
    var toolNames: [String]
    var accentHex: String

    init(skill: Skill) {
        self.name = skill.name
        self.slashCommand = skill.slashCommand
        self.icon = skill.icon
        self.summary = skill.summary
        self.promptPrefix = skill.promptPrefix
        self.triggerKeywords = skill.triggerKeywords
        self.intentLabel = skill.intentLabel
        self.toolNames = skill.toolNames
        self.accentHex = skill.accentHex
    }

    func makeSkill() -> Skill {
        Skill(
            name: name,
            slashCommand: slashCommand.isEmpty ? name : slashCommand,
            icon: icon,
            summary: summary,
            promptPrefix: promptPrefix,
            triggerKeywords: triggerKeywords,
            intentLabel: intentLabel,
            isBuiltin: false,
            toolNames: toolNames,
            accentHex: accentHex
        )
    }
}

/// 导入结果，用于给出准确的反馈文案。
enum SkillImportResult: Sendable {
    case added(count: Int)
    case failure(reason: String)
}

extension Skill {
    /// 内置技能种子数据。
    static func builtinSeeds() -> [Skill] {
        [
            Skill(
                name: "总结",
                slashCommand: "总结",
                icon: "text.append",
                summary: "把长内容压缩成要点清单",
                promptPrefix: "请把下面的内容总结成不超过 5 条要点，每条一行，保留关键数字与结论。",
                triggerKeywords: ["总结", "摘要", "概括", "提炼", "归纳"],
                intentLabel: "summarize",
                sortIndex: 0
            ),
            Skill(
                name: "翻译",
                slashCommand: "翻译",
                icon: "character.book.closed",
                summary: "中英互译，保留术语与语气",
                promptPrefix: "请翻译下面的内容：若是中文则译成地道英文，若是英文则译成中文。保留专有名词与专业术语，不要添加解释，只给出译文。",
                triggerKeywords: ["翻译", "译成", "英文", "中文", "translate"],
                intentLabel: "translate",
                sortIndex: 1
            ),
            Skill(
                name: "润色",
                slashCommand: "润色",
                icon: "wand.and.sparkles",
                summary: "改通顺、改语气，保留原意",
                promptPrefix: "请润色下面的文字：保持原意与信息量不变，改善用词、语气与节奏，输出润色后的版本，并附一行说明改了哪些地方。",
                triggerKeywords: ["润色", "改写", "通顺", "语气", "优化文字"],
                intentLabel: "polish",
                sortIndex: 2
            ),
            Skill(
                name: "解释代码",
                slashCommand: "解释代码",
                icon: "chevron.left.forwardslash.chevron.right",
                summary: "讲清代码在做什么、坑在哪",
                promptPrefix: "请解释下面这段代码：先一句话说它整体在做什么，再逐段说明关键逻辑，最后列出潜在缺陷或风险。",
                triggerKeywords: ["代码", "这段代码", "函数", "报错", "bug", "stack trace", "解释"],
                intentLabel: "explainCode",
                sortIndex: 3
            ),
            Skill(
                name: "写邮件",
                slashCommand: "写邮件",
                icon: "envelope",
                summary: "按场景写出得体的邮件",
                promptPrefix: "请帮我写一封邮件：语气专业得体，结构为称呼、正文要点、明确诉求、结尾礼貌语。默认中文，除非我指定其他语言。",
                triggerKeywords: ["邮件", "回复邮件", "致信", "email", "函"],
                intentLabel: "composeMail",
                sortIndex: 4
            ),
            Skill(
                name: "头脑风暴",
                slashCommand: "头脑风暴",
                icon: "lightbulb.max",
                summary: "给出多角度可选方案",
                promptPrefix: "请针对下面的问题做头脑风暴：给出 8 个方向不同的想法，每条一句，越具体越好，不要评价可行性。",
                triggerKeywords: ["想法", "点子", "方案", "头脑风暴", "创意", "灵感"],
                intentLabel: "brainstorm",
                sortIndex: 5
            )
        ]
    }
}

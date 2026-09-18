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
            ),
            Skill(
                name: "做幻灯片",
                slashCommand: "做幻灯片",
                icon: "rectangle.on.rectangle.angled",
                summary: "逐页输出 PPT 结构与讲稿",
                promptPrefix: """
                请把下面的内容整理成一份演示文稿，逐页输出，每页包含：
                【页码 · 标题】
                要点（不超过 3 条，每条不超过 18 字）
                讲稿备注（一两句话，说明这一页要讲什么）

                写作要求（很重要）：
                - 用具体名词和数字，不要用「赋能」「闭环」「抓手」「生态」「next-generation」这类空话
                - 能用短句就不用长句，能删的形容词就删掉
                - 标题写结论，不要写「关于……的汇报」这种没有信息量的封面标题
                - 每页只讲一件事，不要在一页里堆两个主题
                """,
                triggerKeywords: ["PPT", "ppt", "幻灯片", "演示", "汇报", "deck", "slides", "宣讲"],
                intentLabel: "makeSlides",
                sortIndex: 6
            ),
            Skill(
                name: "写文档",
                slashCommand: "写文档",
                icon: "doc.text",
                summary: "按结论先行的结构写报告",
                promptPrefix: """
                请按下面的结构写一份文档：
                1. 结论先行：开头一段说清楚最终建议或结论
                2. 依据：支撑结论的事实、数据、推理
                3. 其他方案与取舍：为什么不选它们
                4. 行动项：谁在什么时候做什么

                语言要求：直接、具体、少用形容词，不写「随着……的发展」这类套话。
                """,
                triggerKeywords: ["文档", "报告", "方案", "说明书", "白皮书", "总结报告"],
                intentLabel: "writeDocument",
                sortIndex: 7
            ),
            Skill(
                name: "整理表格",
                slashCommand: "整理表格",
                icon: "tablecells",
                summary: "把杂乱信息理成表格",
                promptPrefix: """
                请把下面的信息整理成 Markdown 表格：先根据内容决定列（不超过 6 列），
                每行一条记录，单元格内容尽量简短。表格之后用一句话说明表格里最值得注意的一行。
                如果信息不足以填满整列，宁可留空也不要编造。
                """,
                triggerKeywords: ["表格", "整理成表", "对比表", "清单", "CSV", "列出来"],
                intentLabel: "makeTable",
                sortIndex: 8
            ),
            Skill(
                name: "画流程图",
                slashCommand: "画流程图",
                icon: "flowchart",
                summary: "输出可直接渲染的 Mermaid 图",
                promptPrefix: """
                请用 Mermaid 语法输出一张图，放在 ```mermaid 代码块里：
                流程用 flowchart TD，时序用 sequenceDiagram，状态用 stateDiagram-v2。
                节点文字用中文短语，不要塞长句子；节点数量控制在 12 个以内。
                图之后用两三句话解释关键分支。
                """,
                triggerKeywords: ["流程图", "架构图", "时序图", "关系图", "mermaid", "画个图", "示意图"],
                intentLabel: "drawDiagram",
                sortIndex: 9
            ),
            Skill(
                name: "读长文",
                slashCommand: "读长文",
                icon: "text.book.closed",
                summary: "把长文压成可行动的理解",
                promptPrefix: """
                请阅读下面的长文并输出四部分：
                1. 一句话结论（作者到底想说什么）
                2. 关键论点（3–5 条，每条带原文依据）
                3. 对我的意义（如果我是做……的，该怎么用）
                4. 存疑之处（论据薄弱或与常识冲突的地方）

                不要复述原文，不要写读后感式的空话。
                """,
                triggerKeywords: ["这篇文章", "这份文档", "PDF", "长文", "论文", "读一下", "帮我看看这篇"],
                intentLabel: "readLongform",
                sortIndex: 10
            ),
            Skill(
                name: "会议纪要",
                slashCommand: "会议纪要",
                icon: "list.bullet.rectangle.portrait",
                summary: "把记录整理成决议、待办与待澄清",
                promptPrefix: """
                请把下面的内容整理成会议纪要，固定四段：
                ## 结论
                ## 待办（每条：事项 — 负责人 — 截止时间；缺失的写「未提及」）
                ## 讨论要点（按主题归并，不要按发言顺序记流水账）
                ## 待澄清

                只写记录中确有的信息，不要补充推测；人名、数字、时间要原样保留。
                """,
                triggerKeywords: ["会议", "纪要", "开会", "讨论", "决议", "例会", "复盘"],
                intentLabel: "meetingMinutes",
                sortIndex: 11
            ),
            Skill(
                name: "语音速记",
                slashCommand: "语音速记",
                icon: "waveform.badge.mic",
                summary: "把口语转写整理成书面记录",
                promptPrefix: """
                下面是一段语音转写，可能存在口语、重复、断句错误和同音错别字。
                请整理成通顺的书面记录：
                - 保留原意与所有关键数字、人名、时间
                - 去掉口头语、重复和自我更正
                - 修正明显的同音错字，但不要改动专有名词
                - 按主题分段，必要时加小标题

                不要添加原文没有的信息。如果某句话实在无法理解，原样保留并用「（听不清）」标注。
                """,
                triggerKeywords: ["录音", "转写", "语音记录", "速记", "听写", "整理一下刚才"],
                intentLabel: "voiceNotes",
                sortIndex: 12
            )
        ]
    }
}

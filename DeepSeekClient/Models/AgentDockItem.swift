import Foundation
import SwiftData

/// Agent Dock 中的一个轻量级智能体。
@Model
final class AgentDockItem {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "person.crop.circle"
    var summary: String = ""
    var systemPrompt: String = ""
    var accentHex: String = ""
    var isBuiltin: Bool = true
    var isEnabled: Bool = true
    /// 关联的技能名（与 Skill.name 对应）。
    var skillNames: [String] = []
    /// 允许使用的 MCP 工具名。
    var mcpToolNames: [String] = []
    /// 是否允许把 MCP 返回的数据随对话上传到云端。
    var allowsToolDataUpload: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "person.crop.circle",
        summary: String = "",
        systemPrompt: String = "",
        accentHex: String = "",
        isBuiltin: Bool = true,
        isEnabled: Bool = true,
        skillNames: [String] = [],
        mcpToolNames: [String] = [],
        allowsToolDataUpload: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.summary = summary
        self.systemPrompt = systemPrompt
        self.accentHex = accentHex
        self.isBuiltin = isBuiltin
        self.isEnabled = isEnabled
        self.skillNames = skillNames
        self.mcpToolNames = mcpToolNames
        self.allowsToolDataUpload = allowsToolDataUpload
        self.sortIndex = sortIndex
    }
}

extension AgentDockItem {
    /// 内置胶囊：代码审查、会议纪要、翻译助手。
    static func builtinSeeds() -> [AgentDockItem] {
        [
            AgentDockItem(
                name: "代码审查",
                icon: "ladybug.fill",
                summary: "挑出缺陷与坏味道",
                systemPrompt: """
                你是资深代码审查者。审查代码时按以下顺序输出：
                1) 阻断性问题（会导致错误、崩溃、安全问题）
                2) 逻辑与边界缺陷
                3) 可读性与结构建议
                每条给出：位置、原因、修改建议。不要复述整段代码，不要客套。
                """,
                accentHex: "#5B6CFF",
                skillNames: ["解释代码"],
                mcpToolNames: ["repository.read", "code.search"],
                sortIndex: 0
            ),
            AgentDockItem(
                name: "会议纪要",
                icon: "list.bullet.rectangle.portrait.fill",
                summary: "整理待办、决议与责任人",
                systemPrompt: """
                你是会议记录整理助手。输出结构固定为：
                ## 决议
                ## 待办（每条：事项 — 负责人 — 截止时间）
                ## 待澄清问题
                只写记录中确有的信息，缺失的字段写“未提及”。
                """,
                accentHex: "#00B3A4",
                skillNames: ["总结"],
                mcpToolNames: ["calendar.read"],
                sortIndex: 1
            ),
            AgentDockItem(
                name: "翻译助手",
                icon: "character.bubble.fill",
                summary: "双语互译，术语一致",
                systemPrompt: """
                你是专业翻译。规则：
                1) 默认中英互译，若为其他语言翻译成中文
                2) 保留原文的格式、编号、代码与专有名词
                3) 术语在同一段内保持一致
                4) 只输出译文，不解释
                若原文有歧义，在译文后用一行“注：”说明。
                """,
                accentHex: "#B14BFF",
                skillNames: ["翻译"],
                sortIndex: 2
            )
        ]
    }
}

import Foundation

/// 通用 Skill / Tool 运行时。
///
/// 设计目标：把「技能」从纯提示词前缀升级成**可被模型主动调用的工具**，并且让每个技能
/// 自己声明它需要哪些底层工具（`Skill.toolNames`）。运行时负责三件事：
///
/// 1. **装配**：把已启用的技能折叠成一枚 `use_skill` 工具定义，`skill` 参数的 enum 由
///    当前可用技能动态生成——模型看到的候选列表永远和磁盘上的技能一致。
/// 2. **执行**：模型调用 `use_skill` 时，把该技能的 `summary` / `promptPrefix` 渲染成
///    一段结构化的工具返回，附带它声明的底层工具清单，模型据此继续调用真实工具。
/// 3. **裁剪**：技能激活期间，若它声明了 `toolNames`，就把暴露给模型的工具集收敛到
///    「声明过的 + 必备核心」，既省 token 也降低误调用。
@MainActor
enum SkillToolRuntime {

    /// 技能工具的固定名字。
    static let toolName = "use_skill"

    /// 技能未声明工具时也要保留的核心能力：读写工作区、看时间。
    private static let alwaysAvailable: Set<String> = [
        "current_time",
        "workspace_list",
        "workspace_read",
        "workspace_write"
    ]

    // MARK: - 装配

    /// 把已启用技能装配成一枚 `use_skill` 工具定义。没有技能时返回空数组。
    static func definitions(for skills: [Skill], activeSkill: Skill?) -> [LLMToolDefinition] {
        let enabled = skills.filter(\.isEnabled)
        guard !enabled.isEmpty else { return [] }

        var properties: [String: Any] = [
            "skill": [
                "type": "string",
                "enum": enabled.map(\.name),
                "description": "要启用的技能名称，必须取自枚举值。"
            ],
            "input": [
                "type": "string",
                "description": "交给该技能处理的内容或用户的原始请求；已激活技能可省略。"
            ]
        ]

        var required = ["skill"]
        if let activeSkill, activeSkill.isEnabled {
            properties["skill"] = [
                "type": "string",
                "enum": enabled.map(\.name),
                "description": "当前已预选技能：\(activeSkill.name)。可换成其他枚举值。"
            ]
            required = []
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required
        ]

        let json = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"type":"object","properties":{}}"#

        let names = enabled.prefix(12).map(\.name).joined(separator: "、")
        let description = """
        启用一个专门技能，拿到它的工作指引与所需工具清单。可用技能：\(names)。\
        需要按特定流程处理（总结、翻译、写代码、做纪要等）时先调用它。
        """

        return [
            LLMToolDefinition(name: toolName, description: description, parametersJSON: json)
        ]
    }

    /// 技能声明的底层工具名集合（用于裁剪工具集）。
    static func scopedToolNames(for skills: [Skill], activeSkill: Skill?) -> Set<String>? {
        guard let active = activeSkill ?? skills.first(where: { $0.isEnabled && !$0.toolNames.isEmpty }),
              !active.toolNames.isEmpty
        else { return nil }
        return Set(active.toolNames).union(alwaysAvailable)
    }

    // MARK: - 执行

    static func isSkillTool(_ name: String) -> Bool {
        name == toolName
    }

    /// 执行 `use_skill`：返回技能指引文本。
    static func invoke(argumentsJSON: String, skills: [Skill], activeSkill: Skill?) -> String {
        let args = parse(argumentsJSON)
        let requested = (args["skill"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = (args["input"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let pool = skills.filter(\.isEnabled)
        guard !pool.isEmpty else { return "当前没有启用的技能，请直接完成任务。" }

        let match = requested.flatMap { name in
            pool.first { $0.name == name }
                ?? pool.first { $0.slashCommand == name }
                ?? pool.first { $0.name.localizedCaseInsensitiveContains(name) }
        } ?? activeSkill.flatMap { active in pool.first { $0.id == active.id } }

        guard let skill = match else {
            let names = pool.map(\.name).joined(separator: "、")
            return "没有找到这个技能。可用技能：\(names)。"
        }

        var lines: [String] = ["已启用技能：\(skill.name)"]
        if !skill.summary.isEmpty {
            lines.append("简介：\(skill.summary)")
        }
        if !skill.promptPrefix.isEmpty {
            lines.append("工作指引：\n\(render(skill.promptPrefix, input: input))")
        }
        if !skill.triggerKeywords.isEmpty {
            lines.append("适用关键词：\(skill.triggerKeywords.joined(separator: "、"))")
        }
        let tools = skill.toolNames.isEmpty
            ? Array(alwaysAvailable).sorted()
            : skill.toolNames
        lines.append("建议使用的工具：\(tools.joined(separator: "、"))")
        lines.append("请按上述指引直接产出结果，不要再复述指引内容。")
        return lines.joined(separator: "\n")
    }

    // MARK: - 私有

    private static func render(_ prefix: String, input: String) -> String {
        guard !input.isEmpty else { return prefix }
        if prefix.contains("{{input}}") {
            return prefix.replacingOccurrences(of: "{{input}}", with: input)
        }
        return prefix + "\n\n待处理内容：\n" + input
    }

    private static func parse(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }
}

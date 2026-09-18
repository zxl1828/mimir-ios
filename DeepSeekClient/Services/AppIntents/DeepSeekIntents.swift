import Foundation
import AppIntents

// MARK: - 选择文本后的快捷操作

struct SummarizeTextIntent: AppIntent {
    static var title: LocalizedStringResource { "总结文本" }
    static var description: IntentDescription? { IntentDescription("用 DeepSeek 把一段文字压缩成要点。") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "文本", description: "要总结的内容")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await QuickActionRunner.run(
            systemPrompt: "你是总结助手。只输出要点清单，每条一行，保留关键数字与结论，不要客套话。",
            userText: text
        )
        return .result(value: result, dialog: "总结好了")
    }
}

struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource { "翻译文本" }
    static var description: IntentDescription? { IntentDescription("中英互译，保留术语与原文语气。") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "文本")
    var text: String

    @Parameter(title: "目标语言", default: .chinese)
    var language: LanguageOption

    enum LanguageOption: String, AppEnum {
        case chinese
        case english

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "目标语言" }
        static var caseDisplayRepresentations: [LanguageOption: DisplayRepresentation] {
            [
                .chinese: "中文",
                .english: "英文"
            ]
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let target = language == .chinese ? "中文" : "英文"
        let result = try await QuickActionRunner.run(
            systemPrompt: "你是专业翻译。把输入翻译成\(target)，保留格式与专有名词，只输出译文。",
            userText: text
        )
        return .result(value: result, dialog: "翻译完成")
    }
}

struct PolishTextIntent: AppIntent {
    static var title: LocalizedStringResource { "润色文本" }
    static var description: IntentDescription? { IntentDescription("改善措辞与语气，保持原意不变。") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "文本")
    var text: String

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await QuickActionRunner.run(
            systemPrompt: "你是文字编辑。润色输入内容：保持原意与信息量，改善用词与语气，只输出润色后的正文。",
            userText: text
        )
        return .result(value: result, dialog: "润色完成")
    }
}

struct ExplainCodeIntent: AppIntent {
    static var title: LocalizedStringResource { "解释代码" }
    static var description: IntentDescription? { IntentDescription("讲清这段代码在做什么，以及可能的问题。") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "代码")
    var code: String

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await QuickActionRunner.run(
            systemPrompt: "你是资深工程师。先一句话说明代码整体在做什么，再逐段解释关键逻辑，最后列出潜在风险。",
            userText: code
        )
        return .result(value: result, dialog: "解释完成")
    }
}

struct ComposeMailIntent: AppIntent {
    static var title: LocalizedStringResource { "写邮件" }
    static var description: IntentDescription? { IntentDescription("根据要点写一封得体的邮件。") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "要点", description: "这封邮件要说的事情")
    var outline: String

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await QuickActionRunner.run(
            systemPrompt: "你是商务写作助手。写一封结构清晰的邮件：称呼、正文要点、明确诉求、礼貌结尾。",
            userText: outline
        )
        return .result(value: result, dialog: "邮件写好了")
    }
}

// MARK: - 暴露给 Siri 与 Shortcuts

struct DeepSeekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SummarizeTextIntent(),
            phrases: [
                "用 \(.applicationName) 总结文本",
                "让 \(.applicationName) 帮我总结"
            ],
            shortTitle: "总结文本",
            systemImageName: "text.append"
        )

        AppShortcut(
            intent: TranslateTextIntent(),
            phrases: [
                "用 \(.applicationName) 翻译文本",
                "让 \(.applicationName) 翻译成 \(\.$language)"
            ],
            shortTitle: "翻译文本",
            systemImageName: "character.book.closed"
        )

        AppShortcut(
            intent: PolishTextIntent(),
            phrases: [
                "用 \(.applicationName) 润色文本"
            ],
            shortTitle: "润色文本",
            systemImageName: "wand.and.sparkles"
        )

        AppShortcut(
            intent: ExplainCodeIntent(),
            phrases: [
                "用 \(.applicationName) 解释代码",
                "让 \(.applicationName) 看看这段代码"
            ],
            shortTitle: "解释代码",
            systemImageName: "chevron.left.forwardslash.chevron.right"
        )

        AppShortcut(
            intent: ComposeMailIntent(),
            phrases: [
                "用 \(.applicationName) 写邮件",
                "让 \(.applicationName) 起草一封邮件"
            ],
            shortTitle: "写邮件",
            systemImageName: "envelope"
        )
    }
}

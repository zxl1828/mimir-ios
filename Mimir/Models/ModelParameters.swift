import Foundation

/// 单次请求的模型参数。
struct ModelParameters: Codable, Sendable, Equatable {
    var modelID: String
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var frequencyPenalty: Double
    var presencePenalty: Double
    var systemPrompt: String
    var streamsResponse: Bool

    init(
        modelID: String = "deepseek-chat",
        temperature: Double = 0.6,
        topP: Double = 1.0,
        maxTokens: Int = 4_096,
        frequencyPenalty: Double = 0,
        presencePenalty: Double = 0,
        systemPrompt: String = ModelParameters.defaultSystemPrompt,
        streamsResponse: Bool = true
    ) {
        self.modelID = modelID
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.systemPrompt = systemPrompt
        self.streamsResponse = streamsResponse
    }

    static let defaultSystemPrompt = """
    你是 Mimir 的生活助手，表达自然、可靠、体贴，优先帮助用户处理日常安排、信息整理、决策和沟通。
    先给清晰可执行的回答，再补充必要细节；不确定时明确说明；尊重用户偏好，不编造事实，不堆砌客套话。
    用户明确提出编程任务时再提供技术协助，不要把普通生活问题引向代码。
    """

    static let legacyDeepSeekSystemPrompt = """
    你是 DeepSeek，一个严谨、直接、乐于助人的中文 AI 助手。
    回答遵循以下原则：先给结论，再给必要的解释；不确定时明确说明不确定；
    涉及代码时给出可直接运行的完整片段；不要使用空洞的客套话。
    """

    /// 档位参数应用到当前参数上（档位优先，用户可再单独微调）。
    func applying(_ mode: ThinkingMode) -> ModelParameters {
        var copy = self
        copy.temperature = mode.temperature
        copy.maxTokens = mode.maxTokens
        return copy
    }
}

/// 用量统计。
struct TokenUsage: Codable, Sendable, Equatable {
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var reasoningTokens: Int = 0

    var total: Int { promptTokens + completionTokens + reasoningTokens }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            completionTokens: lhs.completionTokens + rhs.completionTokens,
            reasoningTokens: lhs.reasoningTokens + rhs.reasoningTokens
        )
    }

    static let zero = TokenUsage()
}

/// 自定义模型目录条目。
struct CustomModelEntry: Codable, Sendable, Identifiable, Equatable {
    var id: UUID = UUID()
    var displayName: String
    var modelID: String
    var baseURL: String
    var format: APIKeyFormat
    var source: String
    var note: String
}

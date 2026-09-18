import Foundation

// MARK: - 统一的对话类型
//
// 所有云端协议（OpenAI 兼容 / Anthropic / DeepSeek 原生）都先归一化成
// 这里的类型，业务层只认识这一套结构，替换供应商不需要改任何视图代码。

/// 发给模型的一条消息。
struct LLMChatMessage: Sendable, Codable, Equatable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    var role: Role
    var text: String
    /// 图片附件（JPEG / PNG 原始数据）。
    var images: [Data]
    /// 助手消息请求调用的工具（工具调用回环用）。
    var toolCalls: [LLMToolCall]
    var toolCallID: String?
    var toolName: String?

    init(
        role: Role,
        text: String,
        images: [Data] = [],
        toolCalls: [LLMToolCall] = [],
        toolCallID: String? = nil,
        toolName: String? = nil
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
    }
}

/// 编码任意 JSON 值（把工具 schema 透传给服务端时使用）。
struct AnyEncodable: Encodable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let value as String:
            try container.encode(value)
        case let value as Bool:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as [Any]:
            try container.encode(value.map { AnyEncodable($0) })
        case let value as [String: Any]:
            try container.encode(value.mapValues { AnyEncodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

/// 工具定义（MCP 工具会在运行时转换为该结构）。
struct LLMToolDefinition: Sendable, Codable, Equatable {
    var name: String
    var description: String
    /// JSON Schema 文本。
    var parametersJSON: String
}

/// 模型请求发起的一次工具调用。
struct LLMToolCall: Sendable, Codable, Equatable {
    var id: String
    var name: String
    var argumentsJSON: String
}

/// 流式事件。
enum LLMStreamEvent: Sendable {
    case reasoningDelta(String)
    case textDelta(String)
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsDelta: String)
    case toolCallsReady([LLMToolCall])
    case usage(TokenUsage)
    case finished(reason: String)
}

/// 凭据校验结果。
struct LLMValidationResult: Sendable, Equatable {
    var isReachable: Bool
    var format: APIKeyFormat
    var message: String
    var availableModels: [String]
}

/// 统一错误。
enum LLMError: LocalizedError, Sendable, Equatable {
    case missingCredential
    case invalidURL(String)
    case unauthorized
    case forbidden
    case notFound(String)
    case rateLimited
    case serverError(status: Int, message: String)
    case network(String)
    case decoding(String)
    case cancelled
    case emptyResponse
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "还没有配置 API Key，请先在设置里填写。"
        case .invalidURL(let value):
            return "接口地址无法解析：\(value)"
        case .unauthorized:
            return "API Key 无效或已过期，请重新填写。"
        case .forbidden:
            return "这个 Key 没有访问该模型的权限。"
        case .notFound(let path):
            return "接口地址不存在（\(path)），请检查 Base URL。"
        case .rateLimited:
            return "请求过于频繁或额度已用尽，请稍后再试。"
        case .serverError(let status, let message):
            return "服务端返回 \(status)：\(message)"
        case .network(let message):
            return "网络连接失败：\(message)"
        case .decoding(let message):
            return "返回内容无法解析：\(message)"
        case .cancelled:
            return "已停止生成。"
        case .emptyResponse:
            return "模型没有返回内容。"
        case .unsupported(let message):
            return message
        }
    }

    /// 是否属于“可以重试”的错误（网络抖动、限流、服务端 5xx）。
    var isRetryable: Bool {
        switch self {
        case .network, .rateLimited, .serverError: return true
        default: return false
        }
    }
}

/// 单次生成的统计信息。
struct LLMGenerationSummary: Sendable, Equatable {
    var text: String
    var reasoning: String
    var usage: TokenUsage
    var finishReason: String
    var toolCalls: [LLMToolCall]
    var wasInterrupted: Bool

    static let empty = LLMGenerationSummary(
        text: "",
        reasoning: "",
        usage: .zero,
        finishReason: "",
        toolCalls: [],
        wasInterrupted: false
    )
}

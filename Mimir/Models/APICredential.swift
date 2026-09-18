import Foundation

/// 云端 API 的接入格式。根据 Key 前缀自动识别，
/// 识别后自动配置 base URL 与请求头。
enum APIKeyFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepseekNative
    case openAI
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseekNative: return "DeepSeek 原生"
        case .openAI: return "OpenAI 格式"
        case .anthropic: return "Anthropic 格式"
        }
    }

    var detail: String {
        switch self {
        case .deepseekNative: return "直接调用 DeepSeek 官方接口"
        case .openAI: return "任何 OpenAI 兼容网关（含自建、聚合服务）"
        case .anthropic: return "Anthropic Messages 接口"
        }
    }

    /// 根据前缀识别格式。
    static func detect(from key: String) -> APIKeyFormat {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sk-ant-") { return .anthropic }
        if trimmed.hasPrefix("sk-") { return .openAI }
        return .deepseekNative
    }

    /// 默认服务地址。OpenAI 格式默认走 DeepSeek 的兼容端点，
    /// 用户可在设置里改成任意兼容网关。
    var defaultBaseURL: String {
        switch self {
        case .deepseekNative, .openAI: return "https://api.deepseek.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }

    var defaultModelID: String {
        switch self {
        case .deepseekNative, .openAI: return "deepseek-chat"
        case .anthropic: return "claude-sonnet-4-5"
        }
    }

    /// 该格式对应的传输实现。
    var providerKind: LLMProviderKind {
        switch self {
        case .deepseekNative, .openAI: return .openAICompatible
        case .anthropic: return .anthropic
        }
    }
}

/// 传输实现类别（同一类别下的差异只在请求头与路径）。
enum LLMProviderKind: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

/// 一份完整的接入凭据。仅保存在 Keychain 与本地设置中，绝不硬编码。
struct APICredential: Codable, Sendable, Equatable {
    var key: String
    var format: APIKeyFormat
    var baseURL: String
    var modelID: String
    var organizationID: String?
    var extraHeaders: [String: String]

    init(
        key: String,
        format: APIKeyFormat,
        baseURL: String? = nil,
        modelID: String? = nil,
        organizationID: String? = nil,
        extraHeaders: [String: String] = [:]
    ) {
        self.key = key
        self.format = format
        self.baseURL = baseURL ?? format.defaultBaseURL
        self.modelID = modelID ?? format.defaultModelID
        self.organizationID = organizationID
        self.extraHeaders = extraHeaders
    }

    /// 由用户输入的 Key 自动推断出的凭据。
    static func inferred(from rawKey: String) -> APICredential {
        let format = APIKeyFormat.detect(from: rawKey)
        return APICredential(
            key: rawKey.trimmingCharacters(in: .whitespacesAndNewlines),
            format: format
        )
    }

    var displayKey: String {
        guard key.count > 12 else { return String(repeating: "•", count: max(key.count, 4)) }
        let prefix = key.prefix(6)
        let suffix = key.suffix(4)
        return "\(prefix)••••\(suffix)"
    }

    static let placeholder = APICredential(key: "", format: .deepseekNative)
}

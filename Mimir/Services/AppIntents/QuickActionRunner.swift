import Foundation

/// 快捷指令（Siri / Shortcuts）背后的一次性任务执行器。
///
/// 复用同一套网络层与 Keychain，不额外保存任何内容。
@MainActor
enum QuickActionRunner {

    enum RunnerError: LocalizedError {
        case missingKey
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .missingKey: return "还没有配置 API Key，请先打开 App 完成设置。"
            case .emptyResult: return "模型没有返回内容。"
            }
        }
    }

    /// 执行一次非流式生成。
    static func run(
        systemPrompt: String,
        userText: String,
        settings: AppSettings = AppSettings()
    ) async throws -> String {
        let credential = settings.resolvedCredential
        guard !credential.key.isEmpty else { throw RunnerError.missingKey }

        var parameters = settings.parameters
        parameters.streamsResponse = false
        parameters.systemPrompt = systemPrompt
        parameters.maxTokens = min(parameters.maxTokens, 2_048)

        let client = LLMClientFactory.make(for: credential)
        var collected = ""

        let stream = client.streamChat(
            messages: [LLMChatMessage(role: .user, text: userText)],
            parameters: parameters,
            credential: credential,
            tools: []
        )
        for try await event in stream {
            if case .textDelta(let chunk) = event { collected += chunk }
            if case .finished = event { break }
        }

        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RunnerError.emptyResult }
        return trimmed
    }
}

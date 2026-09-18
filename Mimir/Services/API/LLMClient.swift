import Foundation

/// 云端大模型客户端统一接口。业务层只依赖这个协议。
protocol LLMClient: Sendable {
    var kind: LLMProviderKind { get }

    /// 发起一次流式对话。
    func streamChat(
        messages: [LLMChatMessage],
        parameters: ModelParameters,
        credential: APICredential,
        tools: [LLMToolDefinition]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>

    /// 校验凭据是否可用（首次启动引导与设置页共用）。
    func validate(credential: APICredential) async -> LLMValidationResult
}

extension LLMClient {
    func validate(credential: APICredential) async -> LLMValidationResult {
        let probe = ModelParameters(
            modelID: credential.modelID,
            temperature: 0,
            maxTokens: 16,
            systemPrompt: "",
            streamsResponse: false
        )
        var collected = ""
        var failure: String?

        do {
            for try await event in streamChat(
                messages: [LLMChatMessage(role: .user, text: "ping")],
                parameters: probe,
                credential: credential,
                tools: []
            ) {
                if case .textDelta(let chunk) = event { collected += chunk }
                if case .finished = event { break }
            }
        } catch {
            failure = (error as? LLMError)?.errorDescription ?? error.localizedDescription
        }

        if let failure {
            return LLMValidationResult(
                isReachable: false,
                format: credential.format,
                message: failure,
                availableModels: []
            )
        }

        return LLMValidationResult(
            isReachable: true,
            format: credential.format,
            message: collected.isEmpty ? "连接正常" : "连接正常",
            availableModels: [credential.modelID]
        )
    }
}

/// 依据凭据选择具体实现。
enum LLMClientFactory {
    static func make(for credential: APICredential) -> any LLMClient {
        switch credential.format.providerKind {
        case .openAICompatible:
            return OpenAICompatibleClient()
        case .anthropic:
            return AnthropicClient()
        }
    }
}

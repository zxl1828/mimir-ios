import Foundation

/// OpenAI Chat Completions 兼容实现。
///
/// 同时覆盖 DeepSeek 官方端点与任何第三方兼容网关；
/// `reasoning_content` 字段用于承接 DeepSeek 的思考过程。
struct OpenAICompatibleClient: LLMClient {

    let kind: LLMProviderKind = .openAICompatible

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - 请求体

    private struct RequestBody: Encodable {
        struct StreamOptions: Encodable {
            var include_usage: Bool = true
        }
        struct Message: Encodable {
            struct ImageURL: Encodable { var url: String }
            struct Part: Encodable {
                var type: String
                var text: String?
                var image_url: ImageURL?
            }
            var role: String
            var content: Content
            var tool_call_id: String?
            var name: String?

            enum Content: Encodable {
                case text(String)
                case parts([Part])

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .text(let value):
                        try container.encode(value)
                    case .parts(let parts):
                        try container.encode(parts)
                    }
                }
            }
        }

        var model: String
        var messages: [Message]
        var stream: Bool
        var temperature: Double
        var top_p: Double
        var max_tokens: Int
        var frequency_penalty: Double
        var presence_penalty: Double
        var stream_options: StreamOptions?
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
                var reasoning_content: String?
                var tool_calls: [ToolCallDelta]?
            }
            struct ToolCallDelta: Decodable {
                struct Function: Decodable {
                    var name: String?
                    var arguments: String?
                }
                var index: Int?
                var id: String?
                var function: Function?
            }
            var delta: Delta?
            var finish_reason: String?
        }
        struct Usage: Decodable {
            struct CompletionDetails: Decodable {
                var reasoning_tokens: Int?
            }
            var prompt_tokens: Int?
            var completion_tokens: Int?
            var total_tokens: Int?
            var completion_tokens_details: CompletionDetails?
        }
        var choices: [Choice]?
        var usage: Usage?
        var error: APIError?
    }

    private struct APIError: Decodable {
        var message: String?
        var type: String?
        var code: String?
    }

    // MARK: - 流式对话

    func streamChat(
        messages: [LLMChatMessage],
        parameters: ModelParameters,
        credential: APICredential,
        tools: [LLMToolDefinition]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        messages: messages,
                        parameters: parameters,
                        credential: credential,
                        tools: tools
                    )
                    try await runStream(request: request, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: Self.normalize(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("没有收到有效的响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 2_000 { break }
            }
            throw Self.error(for: http.statusCode, body: body)
        }

        var parser = SSEParser()
        var sawContent = false
        var toolAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = parser.consume(line: line) else { continue }
            try Self.handle(
                payload: event.data,
                sawContent: &sawContent,
                toolAccumulator: &toolAccumulator,
                continuation: continuation
            )
        }

        if let tail = parser.flush() {
            try Self.handle(
                payload: tail.data,
                sawContent: &sawContent,
                toolAccumulator: &toolAccumulator,
                continuation: continuation
            )
        }

        if !toolAccumulator.isEmpty {
            let calls = toolAccumulator
                .sorted { $0.key < $1.key }
                .map { LLMToolCall(id: $0.value.id, name: $0.value.name, argumentsJSON: $0.value.arguments) }
            continuation.yield(.toolCallsReady(calls))
        }
    }

    private static func handle(
        payload: String,
        sawContent: inout Bool,
        toolAccumulator: inout [Int: (id: String, name: String, arguments: String)],
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) throws {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if trimmed == "[DONE]" {
            continuation.yield(.finished(reason: "stop"))
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }

        let chunk: StreamChunk
        do {
            chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
        } catch {
            // 有些网关会夹杂心跳或非标准行，忽略而不是中断整条流。
            return
        }

        if let apiError = chunk.error {
            throw LLMError.serverError(status: 200, message: apiError.message ?? "请求被拒绝")
        }

        if let usage = chunk.usage {
            let reasoning = usage.completion_tokens_details?.reasoning_tokens ?? 0
            continuation.yield(
                .usage(
                    TokenUsage(
                        promptTokens: usage.prompt_tokens ?? 0,
                        completionTokens: max((usage.completion_tokens ?? 0) - reasoning, 0),
                        reasoningTokens: reasoning
                    )
                )
            )
        }

        guard let choice = chunk.choices?.first else { return }

        if let reasoning = choice.delta?.reasoning_content, !reasoning.isEmpty {
            sawContent = true
            continuation.yield(.reasoningDelta(reasoning))
        }

        if let content = choice.delta?.content, !content.isEmpty {
            sawContent = true
            continuation.yield(.textDelta(content))
        }

        if let toolDeltas = choice.delta?.tool_calls {
            for delta in toolDeltas {
                let index = delta.index ?? 0
                var entry = toolAccumulator[index] ?? (id: "", name: "", arguments: "")
                if let id = delta.id, !id.isEmpty { entry.id = id }
                if let name = delta.function?.name, !name.isEmpty { entry.name = name }
                if let arguments = delta.function?.arguments { entry.arguments += arguments }
                toolAccumulator[index] = entry
                continuation.yield(
                    .toolCallDelta(
                        index: index,
                        id: delta.id,
                        name: delta.function?.name,
                        argumentsDelta: delta.function?.arguments ?? ""
                    )
                )
            }
        }

        if let reason = choice.finish_reason, !reason.isEmpty {
            continuation.yield(.finished(reason: reason))
        }
    }

    // MARK: - 组装请求

    private func makeRequest(
        messages: [LLMChatMessage],
        parameters: ModelParameters,
        credential: APICredential,
        tools: [LLMToolDefinition]
    ) throws -> URLRequest {
        guard !credential.key.isEmpty else { throw LLMError.missingCredential }
        guard let url = Self.endpoint(base: credential.baseURL, path: "chat/completions") else {
            throw LLMError.invalidURL(credential.baseURL)
        }

        let body = RequestBody(
            model: parameters.modelID,
            messages: messages.map { message in
                let text = message.text
                let hasImages = !message.images.isEmpty
                let content: RequestBody.Message.Content
                if hasImages {
                    var parts: [RequestBody.Message.Part] = []
                    if !text.isEmpty {
                        parts.append(.init(type: "text", text: text, image_url: nil))
                    }
                    for image in message.images {
                        parts.append(
                            .init(
                                type: "image_url",
                                text: nil,
                                image_url: .init(url: "data:image/jpeg;base64,\(image.base64EncodedString())")
                            )
                        )
                    }
                    content = .parts(parts)
                } else {
                    content = .text(text)
                }
                return RequestBody.Message(
                    role: message.role.rawValue,
                    content: content,
                    tool_call_id: message.toolCallID,
                    name: message.toolName
                )
            },
            stream: parameters.streamsResponse,
            temperature: parameters.temperature,
            top_p: parameters.topP,
            max_tokens: parameters.maxTokens,
            frequency_penalty: parameters.frequencyPenalty,
            presence_penalty: parameters.presencePenalty,
            stream_options: parameters.streamsResponse ? RequestBody.StreamOptions() : nil
        )
        _ = tools // OpenAI 兼容端点的工具定义按需在后续版本注入

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.key)", forHTTPHeaderField: "Authorization")
        if let organization = credential.organizationID, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        for (header, value) in credential.extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// 拼接 Base URL 与路径：兼容带/不带 `/v1` 的写法。
    static func endpoint(base: String, path: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return URL(string: "\(trimmed)/\(path)")
    }

    static func error(for status: Int, body: String) -> LLMError {
        let detail = extractMessage(from: body)
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound(detail.isEmpty ? "接口路径不存在" : detail)
        case 429: return .rateLimited
        default:
            if status >= 500 { return .serverError(status: status, message: detail) }
            return .serverError(status: status, message: detail.isEmpty ? "请求失败" : detail)
        }
    }

    static func extractMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.isEmpty ? "" : String(body.prefix(200))
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String { return message }
        return String(body.prefix(200))
    }

    static func normalize(_ error: Error) -> LLMError {
        if let llm = error as? LLMError { return llm }
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network(nsError.localizedDescription)
        }
        return .network(error.localizedDescription)
    }
}

import Foundation

/// Anthropic Messages 协议实现（`sk-ant-` 前缀的 Key）。
struct AnthropicClient: LLMClient {

    let kind: LLMProviderKind = .anthropic

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            self.session = URLSession(configuration: configuration)
        }
    }

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            struct Part: Encodable {
                struct Source: Encodable {
                    var type: String = "base64"
                    var media_type: String
                    var data: String
                }
                var type: String
                var text: String?
                var source: Source?
            }
            var role: String
            var content: [Part]
        }
        var model: String
        var max_tokens: Int
        var temperature: Double
        var top_p: Double
        var system: String?
        var messages: [Message]
        var stream: Bool
    }

    private struct StreamEvent: Decodable {
        struct MessageStart: Decodable {
            struct Usage: Decodable { var input_tokens: Int? }
            var usage: Usage?
        }
        struct Delta: Decodable {
            var type: String?
            var text: String?
            var stop_reason: String?
        }
        struct Usage: Decodable {
            var output_tokens: Int?
            var input_tokens: Int?
        }
        struct ErrorPayload: Decodable {
            var type: String?
            var message: String?
        }
        var type: String?
        var message: MessageStart?
        var delta: Delta?
        var usage: Usage?
        var error: ErrorPayload?
    }

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
                        credential: credential
                    )
                    try await runStream(request: request, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: OpenAICompatibleClient.normalize(error))
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
            throw OpenAICompatibleClient.error(for: http.statusCode, body: body)
        }

        var parser = SSEParser()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = parser.consume(line: line) else { continue }
            try Self.handle(payload: event.data, continuation: continuation)
        }
        if let tail = parser.flush() {
            try Self.handle(payload: tail.data, continuation: continuation)
        }
    }

    private static func handle(
        payload: String,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) throws {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        guard let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { return }

        if let error = event.error {
            throw LLMError.serverError(status: 200, message: error.message ?? "请求被拒绝")
        }

        switch event.type {
        case "message_start":
            if let inputTokens = event.message?.usage?.input_tokens, inputTokens > 0 {
                continuation.yield(.usage(TokenUsage(promptTokens: inputTokens)))
            }
        case "content_block_delta":
            if let text = event.delta?.text, !text.isEmpty {
                continuation.yield(.textDelta(text))
            }
        case "message_delta":
            if let outputTokens = event.usage?.output_tokens, outputTokens > 0 {
                continuation.yield(.usage(TokenUsage(completionTokens: outputTokens)))
            }
            if let stop = event.delta?.stop_reason, !stop.isEmpty {
                continuation.yield(.finished(reason: stop))
            }
        case "message_stop":
            continuation.yield(.finished(reason: "stop"))
        default:
            break
        }
    }

    private func makeRequest(
        messages: [LLMChatMessage],
        parameters: ModelParameters,
        credential: APICredential
    ) throws -> URLRequest {
        guard !credential.key.isEmpty else { throw LLMError.missingCredential }
        guard let url = OpenAICompatibleClient.endpoint(base: credential.baseURL, path: "messages") else {
            throw LLMError.invalidURL(credential.baseURL)
        }

        let systemText = messages
            .filter { $0.role == .system }
            .map(\.text)
            .joined(separator: "\n\n")

        let conversational = messages
            .filter { $0.role != .system }
            .map { message -> RequestBody.Message in
                var parts: [RequestBody.Message.Part] = []
                if !message.text.isEmpty {
                    parts.append(.init(type: "text", text: message.text, source: nil))
                }
                for image in message.images {
                    parts.append(
                        .init(
                            type: "image",
                            text: nil,
                            source: .init(media_type: "image/jpeg", data: image.base64EncodedString())
                        )
                    )
                }
                if parts.isEmpty {
                    parts.append(.init(type: "text", text: " ", source: nil))
                }
                return RequestBody.Message(
                    role: message.role == .assistant ? "assistant" : "user",
                    content: parts
                )
            }

        let body = RequestBody(
            model: parameters.modelID,
            max_tokens: parameters.maxTokens,
            temperature: parameters.temperature,
            top_p: parameters.topP,
            system: systemText.isEmpty ? nil : systemText,
            messages: conversational,
            stream: parameters.streamsResponse
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(credential.key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        for (header, value) in credential.extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

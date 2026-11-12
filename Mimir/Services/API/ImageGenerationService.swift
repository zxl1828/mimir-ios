import Foundation
import UIKit

/// OpenAI-compatible image generation for providers exposing `/images/generations`.
enum ImageGenerationService {

    private struct RequestBody: Encodable {
        var model: String
        var prompt: String
        var n = 1
        var size: String?
        /// gpt-image-1 只认 b64_json；老接口遇到未知字段会 400，所以只在明确需要时才带。
        var responseFormat: String?

        enum CodingKeys: String, CodingKey {
            case model
            case prompt
            case n
            case size
            case responseFormat = "response_format"
        }
    }

    private struct ResponseBody: Decodable {
        struct Image: Decodable {
            var b64_json: String?
            var url: String?
        }
        var data: [Image]?
    }

    static func generate(
        prompt: String,
        modelID: String,
        size: String? = nil,
        credential: APICredential
    ) async throws -> Data {
        guard credential.format == .openAI else {
            throw LLMError.unsupported("图像生成需要 OpenAI 兼容接口。")
        }
        guard !credential.key.isEmpty else { throw LLMError.missingCredential }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.unsupported("请先描述要生成的图像。")
        }
        guard let endpoint = OpenAICompatibleClient.endpoint(base: credential.baseURL, path: "images/generations") else {
            throw LLMError.invalidURL(credential.baseURL)
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.key)", forHTTPHeaderField: "Authorization")
        if let organization = credential.organizationID, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        for (header, value) in credential.extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let resolvedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredSize = adjustedSize(model: resolvedModel, raw: size)

        do {
            return try await send(
                request: request,
                body: RequestBody(model: resolvedModel, prompt: prompt, n: 1, size: preferredSize)
            )
        } catch let error as LLMError {
            // 各家对 size 的取值很挑剔：gpt-image-1 只认 1024x1024 / 1536x1024 / 1024x1536，
            // 老接口只认 1792x1024 这类，中转站还可能完全不接受这个字段。
            // 被拒时退回"不指定尺寸"再试一次，让服务端用默认值，比直接失败有用得多。
            guard preferredSize != nil, isSizeRejection(error) else { throw error }
            return try await send(
                request: request,
                body: RequestBody(model: resolvedModel, prompt: prompt, n: 1, size: nil)
            )
        }
    }

    /// 服务端是不是在抱怨 size 这个字段（各家措辞不一，只能按关键词判断）。
    private static func isSizeRejection(_ error: LLMError) -> Bool {
        guard case let .serverError(status, message) = error else { return false }
        guard status == 400 || status == 404 || status == 422 else { return false }
        let text = message.lowercased()
        return text.contains("size") || text.contains("dimension") || text.contains("resolution")
    }

    /// 按模型族把画幅换成该接口真正接受的取值。
    private static func adjustedSize(model: String, raw: String?) -> String? {
        guard let raw else { return nil }
        let name = model.lowercased()
        if name.contains("gpt-image") {
            switch raw {
            case "1792x1024": return "1536x1024"
            case "1024x1792": return "1024x1536"
            case "1024x768": return nil          // 4:3 无对应档位，交给服务端默认
            default: return raw
            }
        }
        if name.contains("dall-e-3") {
            switch raw {
            case "1024x768": return nil
            default: return raw
            }
        }
        return raw
    }

    private static func send(request: URLRequest, body: RequestBody) async throws -> Data {
        var request = request
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("没有收到有效的图像生成响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(2_000), encoding: .utf8) ?? ""
            throw OpenAICompatibleClient.error(for: http.statusCode, body: body)
        }

        let result: ResponseBody
        do {
            result = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw LLMError.decoding(error.localizedDescription)
        }
        guard let image = result.data?.first else { throw LLMError.emptyResponse }

        let imageData: Data
        if let encoded = image.b64_json, let decoded = Data(base64Encoded: encoded) {
            imageData = decoded
        } else if let value = image.url, let url = URL(string: value),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            let (download, downloadResponse) = try await URLSession.shared.data(from: url)
            guard let downloadHTTP = downloadResponse as? HTTPURLResponse,
                  (200..<300).contains(downloadHTTP.statusCode) else {
                throw LLMError.network("无法下载生成的图像。")
            }
            imageData = download
        } else {
            throw LLMError.decoding("图像生成服务没有返回有效的图片数据。")
        }

        guard !imageData.isEmpty, imageData.count <= 30_000_000, UIImage(data: imageData) != nil else {
            throw LLMError.decoding("生成的图像为空、无效或超过 30 MB。")
        }
        return imageData
    }
}

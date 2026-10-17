import Foundation
import UIKit

/// OpenAI-compatible image generation for providers exposing `/images/generations`.
enum ImageGenerationService {

    private struct RequestBody: Encodable {
        var model: String
        var prompt: String
        var n = 1
    }

    private struct ResponseBody: Decodable {
        struct Image: Decodable {
            var b64_json: String?
            var url: String?
        }
        var data: [Image]?
    }

    static func generate(prompt: String, modelID: String, credential: APICredential) async throws -> Data {
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
        request.httpBody = try JSONEncoder().encode(RequestBody(model: modelID, prompt: prompt))

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

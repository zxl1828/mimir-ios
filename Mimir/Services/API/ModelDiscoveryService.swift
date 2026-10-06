import Foundation

enum ModelDiscoveryError: LocalizedError {
    case invalidEndpoint
    case unauthorized
    case server(status: Int, message: String)
    case noModels

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Base URL 无效，请检查服务商 API 地址。"
        case .unauthorized: return "API Key 无效或没有读取模型列表的权限。"
        case .server(let status, let message): return "模型列表请求失败（HTTP \(status)）：\(message)"
        case .noModels: return "接口连接成功，但没有返回可用模型。可以手动输入模型 ID。"
        }
    }
}

enum ModelDiscoveryService {
    static func fetchModels(credential: APICredential) async throws -> [String] {
        guard let url = OpenAICompatibleClient.endpoint(base: credential.baseURL, path: "models") else {
            throw ModelDiscoveryError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch credential.format.providerKind {
        case .openAICompatible:
            request.setValue("Bearer \(credential.key)", forHTTPHeaderField: "Authorization")
            if let organization = credential.organizationID, !organization.isEmpty {
                request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
            }
        case .anthropic:
            request.setValue(credential.key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        for (header, value) in credential.extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ModelDiscoveryError.noModels }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let message = (body["error"] as? [String: Any])?["message"] as? String
                ?? body["message"] as? String
                ?? "服务商拒绝了请求"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ModelDiscoveryError.unauthorized
            }
            throw ModelDiscoveryError.server(status: http.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelDiscoveryError.noModels
        }
        let entries = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) ?? []
        let models = entries.compactMap { $0["id"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !models.isEmpty else { throw ModelDiscoveryError.noModels }
        return Array(Set(models)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

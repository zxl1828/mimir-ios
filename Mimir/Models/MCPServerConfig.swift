import Foundation
import SwiftData

/// 一个 MCP 服务器配置。
@Model
final class MCPServerConfig {
    var id: UUID = UUID()
    var name: String = ""
    /// HTTP / SSE 端点。
    var endpoint: String = ""
    /// 是否使用 SSE 流式传输。
    var usesStreaming: Bool = true
    var isEnabled: Bool = true
    /// 该服务器返回的数据是否允许随对话上传到云端模型。
    var allowsDataUpload: Bool = false
    /// 允许模型自动调用该服务器的工具。
    var allowsAutoInvoke: Bool = true
    var lastConnectedAt: Date?
    var cachedToolNames: [String] = []
    var lastError: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        endpoint: String = "",
        usesStreaming: Bool = true,
        isEnabled: Bool = true,
        allowsDataUpload: Bool = false,
        allowsAutoInvoke: Bool = true
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.usesStreaming = usesStreaming
        self.isEnabled = isEnabled
        self.allowsDataUpload = allowsDataUpload
        self.allowsAutoInvoke = allowsAutoInvoke
    }

    var keychainAccount: String { "mcp.token.\(id.uuidString)" }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (URL(string: endpoint)?.host ?? "未命名服务器")
            : name
    }
}

/// 一个可调用的 MCP 工具（已归一化，不依赖具体 SDK 类型）。
struct MCPToolDescriptor: Identifiable, Sendable, Equatable {
    var serverID: UUID
    var serverName: String
    var name: String
    var title: String?
    var summary: String
    var schemaJSON: String
    var allowsDataUpload: Bool

    var id: String { "\(serverID.uuidString)::\(name)" }

    var displayName: String { title ?? name }
}

/// 一次工具调用的结果。
struct MCPToolCallResult: Sendable, Equatable {
    var isError: Bool
    var text: String
    var imageCount: Int
    var rawContentCount: Int
}

import Foundation
import Observation
import MCP

/// MCP 客户端管理：维护多个服务器连接、工具目录与调用进度。
@MainActor
@Observable
final class MCPClientManager {

    static let shared = MCPClientManager()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(toolCount: Int)
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    struct ToolCallProgress: Identifiable, Equatable {
        enum Phase: Equatable {
            case running
            case succeeded
            case failed(String)
        }
        var id = UUID()
        var serverName: String
        var toolName: String
        var phase: Phase
        var detail: String
        var startedAt: Date = Date()
    }

    var states: [UUID: ConnectionState] = [:]
    var toolsByServer: [UUID: [MCPToolDescriptor]] = [:]
    var activeCalls: [ToolCallProgress] = []

    private var clients: [UUID: Client] = [:]
    private var transports: [UUID: any Transport] = [:]

    private init() {}

    // MARK: - 连接

    func connect(config: MCPServerConfig) async {
        let id = config.id
        if states[id]?.isConnected == true { return }

        guard let url = URL(string: config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            states[id] = .failed("地址不合法，请填写完整的 http(s) 地址。")
            return
        }

        states[id] = .connecting

        do {
            let client = Client(name: "Mimir", version: "1.0.0")
            let transport = HTTPClientTransport(endpoint: url, streaming: config.usesStreaming)
            _ = try await client.connect(transport: transport)

            clients[id] = client
            transports[id] = transport

            let descriptors = await loadTools(client: client, config: config)
            toolsByServer[id] = descriptors
            states[id] = .connected(toolCount: descriptors.count)
            config.lastConnectedAt = Date()
            config.lastError = ""
            config.cachedToolNames = descriptors.map(\.name)
        } catch {
            clients[id] = nil
            transports[id] = nil
            let message = error.localizedDescription
            states[id] = .failed(message)
            config.lastError = message
        }
    }

    func disconnect(id: UUID) {
        clients[id] = nil
        transports[id] = nil
        toolsByServer[id] = nil
        states[id] = .disconnected
    }

    func reconnectAll(configs: [MCPServerConfig]) async {
        for config in configs where config.isEnabled {
            await connect(config: config)
        }
    }

    // MARK: - 工具目录

    private func loadTools(client: Client, config: MCPServerConfig) async -> [MCPToolDescriptor] {
        do {
            let (tools, _) = try await client.listTools()
            return tools.map { tool in
                MCPToolDescriptor(
                    serverID: config.id,
                    serverName: config.displayName,
                    name: tool.name,
                    title: tool.title,
                    summary: tool.description ?? "",
                    schemaJSON: Self.schemaJSON(from: tool.inputSchema),
                    allowsDataUpload: config.allowsDataUpload
                )
            }
        } catch {
            config.lastError = error.localizedDescription
            return []
        }
    }

    func allTools(configs: [MCPServerConfig]) -> [MCPToolDescriptor] {
        configs
            .filter { $0.isEnabled }
            .flatMap { toolsByServer[$0.id] ?? [] }
    }

    // MARK: - 调用

    func callTool(
        serverID: UUID,
        toolName: String,
        argumentsJSON: String,
        serverName: String
    ) async -> MCPToolCallResult {
        let progressID = UUID()
        appendProgress(
            ToolCallProgress(
                id: progressID,
                serverName: serverName,
                toolName: toolName,
                phase: .running,
                detail: "正在调用…"
            )
        )

        guard let client = clients[serverID] else {
            finishProgress(progressID, phase: .failed("服务器未连接"), detail: "请先在设置里连接该 MCP 服务器。")
            return MCPToolCallResult(
                isError: true,
                text: "MCP 服务器未连接，工具 \(toolName) 无法执行。",
                imageCount: 0,
                rawContentCount: 0
            )
        }

        do {
            let arguments = try Self.decodeArguments(argumentsJSON)
            let (content, isError) = try await client.callTool(name: toolName, arguments: arguments)
            let failed = isError ?? false
            let text = Self.plainText(from: content)
            let images = content.filter {
                Self.kindName(of: $0) == "image"
            }.count

            finishProgress(
                progressID,
                phase: failed ? .failed("工具返回错误") : .succeeded,
                detail: failed ? String(text.prefix(60)) : "完成"
            )

            return MCPToolCallResult(
                isError: failed,
                text: text,
                imageCount: images,
                rawContentCount: content.count
            )
        } catch {
            finishProgress(progressID, phase: .failed(error.localizedDescription), detail: "")
            return MCPToolCallResult(
                isError: true,
                text: "工具调用失败：\(error.localizedDescription)",
                imageCount: 0,
                rawContentCount: 0
            )
        }
    }

    // MARK: - 进度

    private func appendProgress(_ value: ToolCallProgress) {
        activeCalls.append(value)
        if activeCalls.count > 6 {
            activeCalls.removeFirst(activeCalls.count - 6)
        }
    }

    private func finishProgress(_ id: UUID, phase: ToolCallProgress.Phase, detail: String) {
        guard let index = activeCalls.firstIndex(where: { $0.id == id }) else { return }
        activeCalls[index].phase = phase
        activeCalls[index].detail = detail

        // 成功条目短暂保留后自动淡出，失败条目留着提示。
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self else { return }
            if case .succeeded = phase {
                self.activeCalls.removeAll { $0.id == id }
            }
        }
    }

    func clearFinishedCalls() {
        activeCalls.removeAll { progress in
            if case .succeeded = progress.phase { return true }
            return false
        }
    }

    // MARK: - 序列化工具

    static func schemaJSON(from value: Value) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(value),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        return #"{"type":"object","properties":{}}"#
    }

    /// 模型给出的参数是 JSON 字符串，这里转回 MCP 的 Value 字典。
    static func decodeArguments(_ json: String) throws -> [String: Value] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let data = trimmed.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Value].self, from: data)) ?? [:]
    }

    /// 把工具返回的内容压成一段纯文本，供模型继续推理。
    ///
    /// SDK 对内容类型有多个近似定义，这里用反射读取枚举负载，
    /// 避免把实现细节写死在某一个 case 形状上。
    static func plainText(from content: [Tool.Content]) -> String {
        let parts: [String] = content.map { item in
            let kind = kindName(of: item)
            switch kind {
            case "text":
                return stringPayload(of: item) ?? String(describing: item)
            case "image":
                return "[图片结果，已在本地接收]"
            case "audio":
                return "[音频结果]"
            case "resource":
                return "[嵌入资源]"
            case "resourceLink":
                return "[资源链接]"
            default:
                return String(describing: item)
            }
        }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? "（工具没有返回内容）" : joined
    }

    /// 反射读取枚举 case 名称。
    private static func kindName(of item: Tool.Content) -> String {
        let mirror = Mirror(reflecting: item)
        if let label = mirror.children.first?.label {
            return label
        }
        let description = String(describing: item)
        if let name = description.split(separator: "(").first {
            return String(name)
        }
        return description
    }

    /// 从负载里取出文本：既支持 `case text(String)`，也支持带标签的元组形式。
    private static func stringPayload(of item: Tool.Content) -> String? {
        guard let child = Mirror(reflecting: item).children.first else { return nil }
        if let value = child.value as? String { return value }
        for sub in Mirror(reflecting: child.value).children where sub.label == "text" {
            if let value = sub.value as? String { return value }
        }
        return nil
    }
}

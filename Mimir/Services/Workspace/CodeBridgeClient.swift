import Foundation
import Observation

/// 「代码工坊」的桥接客户端。
///
/// 电脑端跑 `tools/code_server.py`，这里轮询它，把 AI 正在编辑的源码文件
/// 实时拉到手机上显示：
/// - `/status` 拿到"最近被修改的文件"（AI 正在改的那个）
/// - 文件路径变了，或者 mtime 变了，就重新拉 `/file` 内容
/// - 只在「代码工坊」页可见时轮询（`startAutoSync` / `stopAutoSync`），省电
///
/// 内容只有 mtime 真的变化时才替换，并且用等值判断挡住重复刷新——
/// 避免 AI 高频写盘时画面来回跳动。
@MainActor
@Observable
final class CodeBridgeClient {

    static let shared = CodeBridgeClient()

    // MARK: - 数据模型

    struct RemoteStatus: Sendable, Equatable {
        var file: String?
        var mtime: Double
        var editedAgo: Double
        var count: Int
    }

    /// 一次文件快照；`Equatable` 用于挡住无意义的重绘。
    struct FileSnapshot: Sendable, Equatable {
        var path: String
        var mtime: Double
        var lines: Int
        var content: String
    }

    // MARK: - 状态

    private(set) var endpoint: String
    private(set) var isConnected = false
    private(set) var status: RemoteStatus?
    private(set) var snapshot: FileSnapshot?
    private(set) var lastError: String?
    private(set) var isSyncing = false
    /// 最近一次成功同步的时间，用于界面显示"x 秒前同步"。
    private(set) var lastSyncedAt: Date?

    // MARK: - 内部

    private let endpointKey = "code.bridge.endpoint.v1"
    private let pollInterval: Duration = .milliseconds(1_500)
    private var syncTask: Task<Void, Never>?

    private init() {
        endpoint = UserDefaults.standard.string(forKey: endpointKey) ?? ""
    }

    var hasEndpoint: Bool { !endpoint.isEmpty }

    // MARK: - 配置

    func updateEndpoint(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        endpoint = trimmed
        UserDefaults.standard.set(trimmed, forKey: endpointKey)
        if trimmed.isEmpty {
            stopAutoSync()
            isConnected = false
            status = nil
            snapshot = nil
            lastError = nil
        } else {
            startAutoSync()
        }
    }

    // MARK: - 自动同步

    func startAutoSync() {
        guard hasEndpoint, syncTask == nil else { return }
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
            }
        }
    }

    func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
    }

    /// 立刻同步一次（用户下拉或手动点刷新时用）。
    func refreshNow() async {
        await refreshOnce()
    }

    // MARK: - 同步主流程

    private func refreshOnce() async {
        guard hasEndpoint, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let status = try await fetchStatus()
            self.status = status
            isConnected = true
            lastError = nil

            guard let file = status.file else {
                lastSyncedAt = Date()
                return
            }

            // 路径没变且 mtime 没变 → 不重新拉内容，画面自然稳定。
            if let current = snapshot, current.path == file, current.mtime == status.mtime {
                lastSyncedAt = Date()
                return
            }

            let fresh = try await fetchFile(path: file)
            if fresh != snapshot {
                snapshot = fresh
            }
            lastSyncedAt = Date()
        } catch {
            isConnected = false
            lastError = error.localizedDescription
        }
    }

    // MARK: - 网络

    private struct StatusPayload: Decodable {
        var ok: Bool
        var file: String?
        var mtime: Double?
        var edited_ago: Double?
        var count: Int?
    }

    private struct FilePayload: Decodable {
        var ok: Bool
        var path: String?
        var mtime: Double?
        var lines: Int?
        var content: String?
    }

    enum BridgeError: LocalizedError {
        case badEndpoint
        case serverMessage(String)

        var errorDescription: String? {
            switch self {
            case .badEndpoint: return "桥接地址无效"
            case .serverMessage(let text): return text
            }
        }
    }

    private func fetchStatus() async throws -> RemoteStatus {
        let payload: StatusPayload = try await get(path: "status")
        guard payload.ok else { throw BridgeError.serverMessage("状态查询失败") }
        return RemoteStatus(
            file: payload.file,
            mtime: payload.mtime ?? 0,
            editedAgo: payload.edited_ago ?? 0,
            count: payload.count ?? 0
        )
    }

    private func fetchFile(path: String) async throws -> FileSnapshot {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let payload: FilePayload = try await get(path: "file?path=\(encoded)")
        guard payload.ok, let content = payload.content, let resolved = payload.path else {
            throw BridgeError.serverMessage(payload.ok ? "文件内容为空" : "读取失败")
        }
        return FileSnapshot(
            path: resolved,
            mtime: payload.mtime ?? 0,
            lines: payload.lines ?? (content.isEmpty ? 1 : content.components(separatedBy: "\n").count),
            content: content
        )
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: "\(endpoint)/\(path)") else {
            throw BridgeError.badEndpoint
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BridgeError.serverMessage("服务返回 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

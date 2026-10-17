import Foundation
import Observation

/// 知识上下文切片节点（RAG Orbit 粒子节点）。
public struct RAGOrbitalNode: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let fileExtension: String
    public let chunkIndex: Int
    public let totalChunks: Int
    public let snippet: String
    public var isCausticActive: Bool
    public var lastReferencedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        fileExtension: String,
        chunkIndex: Int = 0,
        totalChunks: Int = 1,
        snippet: String,
        isCausticActive: Bool = false,
        lastReferencedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.fileExtension = fileExtension
        self.chunkIndex = chunkIndex
        self.totalChunks = totalChunks
        self.snippet = snippet
        self.isCausticActive = isCausticActive
        self.lastReferencedAt = lastReferencedAt
    }
}

/// 赛博猫头鹰 RAG 知识共振中枢：管理当前会话上下文文件与实时 SSE 流引用高亮。
@Observable
@MainActor
public final class RAGContextManager: Sendable {
    public static let shared = RAGContextManager()

    /// 环绕猫头鹰星轨的 1 到 6 个动态知识节点
    public private(set) var orbitalNodes: [RAGOrbitalNode] = []

    /// 当前选中的节点（展开悬浮卡片）
    public var selectedNode: RAGOrbitalNode?

    /// 焦散共振激活任务字典
    @ObservationIgnored
    private var flareResetTasks: [UUID: Task<Void, Never>] = [:]

    public init() {
        // 装填默认对话/架构上下文样本（1~6个）
        seedDefaultContextNodes()
    }

    /// 根据当前工作区或会话更新关联上下文文件（最多 6 个节点）
    public func updateContextFiles(_ files: [(name: String, ext: String, snippet: String)]) {
        let limited = Array(files.prefix(6))
        if limited.isEmpty {
            seedDefaultContextNodes()
            return
        }

        orbitalNodes = limited.enumerated().map { index, file in
            RAGOrbitalNode(
                title: file.name,
                fileExtension: file.ext.lowercased(),
                chunkIndex: index,
                totalChunks: limited.count,
                snippet: file.snippet
            )
        }
    }

    /// 当 SSE 流解析出引用标记或代码块时触发焦散光晕闪烁
    public func triggerCausticFlare(matchingKeyword keyword: String) {
        guard let index = orbitalNodes.firstIndex(where: {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            $0.snippet.localizedCaseInsensitiveContains(keyword)
        }) else { return }

        triggerCausticFlare(nodeID: orbitalNodes[index].id)
    }

    /// 激活特定节点的焦散光晕呼吸脉冲（#7D52F4 8pt 呼吸）
    public func triggerCausticFlare(nodeID: UUID) {
        guard let index = orbitalNodes.firstIndex(where: { $0.id == nodeID }) else { return }

        // 重设当前定时器
        flareResetTasks[nodeID]?.cancel()

        orbitalNodes[index].isCausticActive = true
        orbitalNodes[index].lastReferencedAt = Date()

        flareResetTasks[nodeID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled, let self else { return }
            if let idx = self.orbitalNodes.firstIndex(where: { $0.id == nodeID }) {
                self.orbitalNodes[idx].isCausticActive = false
            }
        }
    }

    /// 装填初始高价值上下文切片
    private func seedDefaultContextNodes() {
        orbitalNodes = [
            RAGOrbitalNode(
                title: "AppTheme.swift",
                fileExtension: "swift",
                chunkIndex: 0,
                totalChunks: 3,
                snippet: "enum AppUI {\n    static let irisViolet = Color(hex: \"7D52F4\")\n    static let deepPlum = Color(hex: \"120D1D\")\n}"
            ),
            RAGOrbitalNode(
                title: "VoiceDuplex.swift",
                fileExtension: "swift",
                chunkIndex: 1,
                totalChunks: 4,
                snippet: "struct VoiceDuplexView: View {\n    // ADA-grade Liquid Glass Sphere with dual-channel typewriter slab\n}"
            ),
            RAGOrbitalNode(
                title: "DesignDNA.md",
                fileExtension: "md",
                chunkIndex: 0,
                totalChunks: 2,
                snippet: "# Mimir Design DNA\nStrictly NO Color.black. Rigid floating slabs with ultraThinMaterial and iris violet caustic highlights."
            ),
            RAGOrbitalNode(
                title: "WorkspaceManager",
                fileExtension: "swift",
                chunkIndex: 2,
                totalChunks: 5,
                snippet: "func mountFolder(url: URL, bookmarkData: Data) async throws {\n    // Security-scoped bookmark persistence for iOS\n}"
            )
        ]
    }
}

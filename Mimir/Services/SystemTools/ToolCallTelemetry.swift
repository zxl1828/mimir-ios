import Foundation
import Observation

/// 工具调用与本地数据访问的遥测中心。
///
/// 每次工具执行记一条（名称 / 起止时间 / 状态 / 参数与结果摘要），
/// 涉及系统框架的数据读取再单独记一条访问记录，供助手消息卡片底部的
/// 遥测胶囊与审计面板展示。
///
/// 全部只存在内存里：不落盘、不外发，退出 App 即清空。
@MainActor
@Observable
final class ToolCallTelemetry {

    static let shared = ToolCallTelemetry()

    // MARK: - 记录模型

    struct ToolInvocation: Identifiable, Sendable {
        let id: UUID
        var name: String
        var startedAt: Date
        var finishedAt: Date?
        var succeeded: Bool?
        var argumentsSummary: String
        var resultSummary: String
        var messageID: UUID?

        var duration: TimeInterval? {
            finishedAt.map { $0.timeIntervalSince(startedAt) }
        }

        var statusText: String {
            guard let succeeded else { return "执行中" }
            return succeeded ? "成功" : "失败"
        }
    }

    struct LocalDataAccess: Identifiable, Sendable {
        let id: UUID
        var framework: String
        var detail: String
        var occurredAt: Date
        var messageID: UUID?
    }

    // MARK: - 状态

    private(set) var invocations: [ToolInvocation] = []
    private(set) var accesses: [LocalDataAccess] = []

    /// 只保留最近这些条，避免长会话把内存撑起来。
    private let limit = 200

    private init() {}

    // MARK: - 写入

    /// 开始一次工具调用；返回的 id 用于结束时回填状态与结果。
    @discardableResult
    func beginTool(name: String, argumentsJSON: String, messageID: UUID?) -> UUID {
        let record = ToolInvocation(
            id: UUID(),
            name: name,
            startedAt: Date(),
            finishedAt: nil,
            succeeded: nil,
            argumentsSummary: Self.summarize(argumentsJSON, limit: 160),
            resultSummary: "",
            messageID: messageID
        )
        invocations.append(record)
        if invocations.count > limit {
            invocations.removeFirst(invocations.count - limit)
        }
        return record.id
    }

    func finishTool(id: UUID, succeeded: Bool, result: String) {
        guard let index = invocations.firstIndex(where: { $0.id == id }) else { return }
        invocations[index].finishedAt = Date()
        invocations[index].succeeded = succeeded
        invocations[index].resultSummary = Self.summarize(result, limit: 200)
    }

    func recordAccess(framework: String, detail: String, messageID: UUID?) {
        accesses.append(
            LocalDataAccess(
                id: UUID(),
                framework: framework,
                detail: detail,
                occurredAt: Date(),
                messageID: messageID
            )
        )
        if accesses.count > limit {
            accesses.removeFirst(accesses.count - limit)
        }
    }

    // MARK: - 查询

    func invocations(for messageID: UUID) -> [ToolInvocation] {
        invocations.filter { $0.messageID == messageID }
    }

    func accesses(for messageID: UUID) -> [LocalDataAccess] {
        accesses.filter { $0.messageID == messageID }
    }

    /// 卡片胶囊用的计数。
    func counts(for messageID: UUID) -> (tools: Int, accesses: Int) {
        (
            invocations.reduce(0) { $0 + ($1.messageID == messageID ? 1 : 0) },
            accesses.reduce(0) { $0 + ($1.messageID == messageID ? 1 : 0) }
        )
    }

    func clear() {
        invocations.removeAll()
        accesses.removeAll()
    }

    // MARK: - 辅助

    /// 把参数 / 结果压成一行摘要（折叠换行 + 截断）。
    private static func summarize(_ text: String, limit: Int) -> String {
        let single = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard single.count > limit else { return single }
        return String(single.prefix(limit)) + "…"
    }

    /// 把本地工具名映射成"本机数据访问"记录，供审计面板展示。
    ///
    /// 后续接入 EventKit / Contacts / WeatherKit 等系统能力时，在这里补映射即可。
    static func localAccess(for toolName: String) -> (framework: String, detail: String)? {
        switch toolName {
        case "ocr_extract_text":
            return ("Vision", "识别图片中的文字")
        case "barcode_scan":
            return ("Vision", "扫描条形码与二维码")
        case "spotlight_search":
            return ("CoreSpotlight", "检索本机索引")
        case "web_search":
            return ("URLSession", "联网检索公开网页")
        case SystemCapabilityGateway.timeTool:
            return ("Foundation", "读取设备时间与时区")
        case SystemCapabilityGateway.calendarReadTool:
            return ("EventKit", "读取日历日程")
        case SystemCapabilityGateway.calendarCreateTool:
            return ("EventKit", "写入日历日程")
        case SystemCapabilityGateway.reminderCreateTool:
            return ("EventKit", "创建提醒事项")
        case SystemCapabilityGateway.contactsSearchTool:
            return ("Contacts", "检索通讯录")
        case SystemCapabilityGateway.dialTool:
            return ("Telephony", "准备拨号")
        case SystemCapabilityGateway.shareTool:
            return ("UIKit", "准备分享内容")
        case SystemCapabilityGateway.locationTool:
            return ("CoreLocation", "获取当前位置")
        case SystemCapabilityGateway.poiTool:
            return ("MapKit", "检索地点")
        case SystemCapabilityGateway.exportTool:
            return ("FileManager", "导出文件到本机")
        case SystemCapabilityGateway.workspaceListTool:
            return ("FileManager", "列出本地工作区文件")
        case SystemCapabilityGateway.workspaceReadTool:
            return ("FileManager", "读取本地工作区文件")
        case SystemCapabilityGateway.workspaceWriteTool:
            return ("FileManager", "写入本地工作区文件")
        default:
            return nil
        }
    }
}

import Foundation
import Observation

/// 任务面板：把 Agent 的推进计划摆到明面上。
///
/// DSH 客户端里那张「任务 · 1 进行中 · 7 待处理」的卡片就是它。
/// 模型通过 `update_plan` 工具提交计划，这里只负责存与展示，
/// 顺手把进度回灌给灵动岛的运行中提示。
@MainActor
@Observable
final class TaskBoardStore {

    static let shared = TaskBoardStore()

    enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    struct Item: Identifiable, Sendable {
        let id = UUID()
        var title: String
        var status: Status
    }

    /// 从工具参数里解析出来的一步。独立成 Sendable 类型，
    /// 这样它可以安全地从后台派发线程带进主线程的 apply。
    struct PlannedStep: Sendable, Hashable {
        var title: String
        var status: Status?
    }

    struct ParsedPlan: Sendable {
        var steps: [PlannedStep]
        var explanation: String
    }

    private(set) var items: [Item] = []
    private(set) var updatedAt: Date?

    private init() {}

    var isEmpty: Bool { items.isEmpty }
    var total: Int { items.count }
    var inProgressCount: Int { items.filter { $0.status == .inProgress }.count }
    var pendingCount: Int { items.filter { $0.status == .pending }.count }
    var completedCount: Int { items.filter { $0.status == .completed }.count }

    /// 卡片副标题：「1 进行中 · 7 待处理」
    var summaryLine: String {
        var parts: [String] = []
        if inProgressCount > 0 { parts.append("\(inProgressCount) 进行中") }
        if pendingCount > 0 { parts.append("\(pendingCount) 待处理") }
        if inProgressCount == 0 && pendingCount == 0 && completedCount > 0 {
            parts.append("\(completedCount) 已完成")
        }
        return parts.joined(separator: " · ")
    }

    /// 当前进行中或最靠前的未完成项，用于灵动岛的那行小字。
    var activeTitle: String? {
        items.first { $0.status == .inProgress }?.title
            ?? items.first { $0.status == .pending }?.title
    }

    func reset() {
        items = []
        updatedAt = nil
    }

    /// 整体替换计划。没给状态的步骤按顺序推断：第一条未完成标成进行中。
    func apply(steps: [PlannedStep]) {
        var mapped: [Item] = []
        var hasActive = false
        for step in steps {
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var status = step.status
            if status == nil {
                if hasActive {
                    status = .pending
                } else {
                    status = .inProgress
                    hasActive = true
                }
            }
            if status == .inProgress, hasActive, mapped.contains(where: { $0.status == .inProgress }) {
                // 只允许一个进行中，多余的降级为待处理。
                status = .pending
            }
            if status == .inProgress { hasActive = true }
            mapped.append(Item(title: title, status: status ?? .pending))
        }
        items = Array(mapped.prefix(24))
        updatedAt = Date()
    }

    /// 把全部未完成项标成已完成（一次任务收尾时调用）。
    func completeAll() {
        guard !items.isEmpty else { return }
        for index in items.indices {
            items[index].status = .completed
        }
        updatedAt = Date()
    }

    /// 从 `update_plan` 的参数里解析。
    nonisolated static func parse(argumentsJSON: String) -> ParsedPlan? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let explanation = (object["explanation"] as? String) ?? ""
        var steps: [PlannedStep] = []

        if let plan = object["plan"] as? [[String: Any]] {
            for entry in plan {
                let title = (entry["step"] as? String)
                    ?? (entry["title"] as? String)
                    ?? (entry["content"] as? String)
                    ?? ""
                let status = (entry["status"] as? String).flatMap(Status.init(rawValue:))
                steps.append(PlannedStep(title: title, status: status))
            }
        }

        if steps.isEmpty, let plain = object["steps"] as? [String] {
            steps = plain.map { PlannedStep(title: $0, status: nil) }
        }
        if steps.isEmpty, let todos = object["todos"] as? [[String: Any]] {
            for entry in todos {
                let title = (entry["content"] as? String) ?? (entry["title"] as? String) ?? ""
                let status = (entry["status"] as? String).flatMap(Status.init(rawValue:))
                steps.append(PlannedStep(title: title, status: status))
            }
        }

        guard !steps.isEmpty else { return nil }
        return ParsedPlan(steps: steps, explanation: explanation)
    }
}

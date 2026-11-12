import Foundation
import Observation

/// 挂载链路诊断台。
///
/// 「点了没反应」这种反馈没法排查：选择器到底有没有弹出来、回调有没有回来、
/// 安全作用域有没有拿到、文件树扫到几层——中间任何一步静默失败，用户看到的现象
/// 都一样。所以把链路拆成带时间戳的步骤，逐步记账，界面上可随时查看。
@MainActor
@Observable
final class MountDiagnostics {

    static let shared = MountDiagnostics()

    struct Step: Identifiable, Hashable {
        let id = UUID()
        let at: Date
        let title: String
        let detail: String
        let isFailure: Bool
    }

    private(set) var steps: [Step] = []
    private(set) var lastAttemptAt: Date?

    private init() {}

    func reset() {
        steps.removeAll()
        lastAttemptAt = nil
    }

    func begin(_ title: String) {
        lastAttemptAt = Date()
        record(title, "开始", isFailure: false)
    }

    func record(_ title: String, _ detail: String, isFailure: Bool = false) {
        steps.append(Step(at: Date(), title: title, detail: detail, isFailure: isFailure))
        if steps.count > 40 {
            steps.removeFirst(steps.count - 40)
        }
    }

    func failure(_ title: String, _ detail: String) {
        record(title, detail, isFailure: true)
    }

    var hasFailure: Bool { steps.contains { $0.isFailure } }

    var summaryLine: String {
        guard let last = steps.last else { return "还没有挂载记录" }
        return "\(last.title) · \(last.detail)"
    }
}

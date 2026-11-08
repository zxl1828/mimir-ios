import ActivityKit
import Foundation
import UIKit

/// 灵动岛「运行中进展」的统一出口。
///
/// 设计取舍：
/// - **不去抢活动所有权**。App 里已经有两种 `ChatActivityAttributes` 活动（常驻待命
///   的 Spark、一次性的对话活动），谁先谁后完全看启动顺序。这里改成"把当前所有
///   活着的活动都更新一遍"——系统只显示最近的那一条，效果一致，却不会出现
///   "常驻活动被 end 掉、灵动岛干脆什么都不显示"的老问题。
/// - **节流**。Live Activity 的更新有系统预算（每小时有限次），工具调用可能一秒
///   好几次，所以除非 `force`，两次推送至少间隔 0.9 秒。
/// - **计时交给系统**。`startedAt` 交给 Widget 的 `Text(_, style: .timer)` 自己走，
///   App 不必每隔一秒推一次——这条也是预算能撑住的关键。
@MainActor
enum GenerationProgressCenter {

    /// 上一次推送时间，用于节流。
    private static var lastPushAt: Date = .distantPast
    /// 系统关闭了实时活动 / 用户在设置里关掉时，整条链路都要安静退出。
    private static var minimumInterval: TimeInterval = 0.9

    private(set) static var isRunning = false
    private(set) static var currentStep = 0

    // MARK: - 生命周期

    /// 开始一轮生成：写入任务标题、工作区、起始时间，并把状态切到"执行中"。
    static func begin(taskTitle: String, workspaceName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        isRunning = true
        currentStep = 0
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = title.isEmpty ? "正在处理你的请求" : String(title.prefix(38))
        let workspace = workspaceName.isEmpty ? defaultWorkspaceName() : workspaceName

        if Activity<ChatActivityAttributes>.activities.isEmpty {
            let attributes = ChatActivityAttributes(conversationID: "mimir.progress")
            let state = ChatActivityAttributes.ContentState(
                conversationTitle: clipped,
                statusText: "执行中",
                previewText: "",
                isGenerating: true,
                tokenCount: 0,
                taskTitle: clipped,
                toolDetail: "准备开始…",
                toolName: "",
                progressStep: 0,
                progressTotal: 0,
                rounds: 0,
                startedAt: Date(),
                workspaceName: workspace
            )
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastPushAt = Date()
            return
        }

        push(force: true) { state in
            state.isGenerating = true
            state.statusText = "执行中"
            state.taskTitle = clipped
            state.conversationTitle = clipped
            state.workspaceName = workspace
            state.startedAt = Date()
            state.progressStep = 0
            state.progressTotal = 0
            state.rounds = 0
            state.toolDetail = "准备开始…"
            state.toolName = ""
        }
    }

    /// 报告一步进展。
    ///
    /// - Parameters:
    ///   - index: 第几步（从 1 开始）。
    ///   - total: 总步数；未知传 0。
    ///   - detail: 一句话动作，例如「准备调用 compress」。
    ///   - toolName: 工具名，用于选择图标。
    static func step(index: Int, total: Int = 0, detail: String, toolName: String = "", rounds: Int = 0) {
        guard isRunning else { return }
        currentStep = max(currentStep, index)
        push { state in
            state.isGenerating = true
            state.statusText = "执行中"
            state.progressStep = index
            state.progressTotal = max(total, state.progressTotal)
            state.toolDetail = String(detail.prefix(60))
            state.toolName = toolName
            if rounds > 0 { state.rounds = rounds }
        }
    }

    /// 结束本轮：把状态条切成完成 / 取消，并保留最后一段正文做预览。
    static func finish(status: String, preview: String) {
        guard isRunning else { return }
        isRunning = false
        push(force: true) { state in
            state.isGenerating = false
            state.statusText = status
            state.previewText = String(preview.suffix(160))
            state.toolDetail = status
            state.toolName = ""
        }
    }

    /// 回到待命（例如用户退出对话页后 3 秒）。
    static func idle() {
        isRunning = false
        currentStep = 0
        push { state in
            guard !state.isGenerating else { return }
            state.statusText = "待命"
            state.toolDetail = ""
            state.toolName = ""
            state.progressStep = 0
        }
    }

    // MARK: - 内部

    /// 完成后延时收起**一次性**活动；常驻待命态（Spark）保留不动。
    static func scheduleDismissal(after seconds: TimeInterval = 10) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            for activity in Activity<ChatActivityAttributes>.activities
            where !activity.content.state.isResident {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func push(force: Bool = false, _ body: (inout ChatActivityAttributes.ContentState) -> Void) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPushAt) >= minimumInterval else { return }
        lastPushAt = now
        let activities = Activity<ChatActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        for activity in activities {
            var state = activity.content.state
            body(&state)
            state.updatedAt = now
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    private static func defaultWorkspaceName() -> String {
        let device = UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name
        let folder = WorkspaceManager.shared.activeWorkspaceURL?.lastPathComponent
        if let folder, !folder.isEmpty {
            return "\(device) · \(folder)"
        }
        return "\(device) · Mimir"
    }
}

import Foundation
import BackgroundTasks

/// 后台任务调度。
///
/// 所有后台任务都需要用户显式授权，注册动作在 App 启动早期完成。
enum BackgroundTaskScheduler {

    static let refreshIdentifier = "com.zxl.deepseekclient.refresh"
    static let briefIdentifier = "com.zxl.deepseekclient.dailybrief"

    private static let briefHourKey = "background.brief.hour"
    private static let briefEnabledKey = "background.brief.enabled"

    /// 在 App 启动早期调用。
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleRefresh(refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: briefIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleDailyBrief(processingTask)
        }
    }

    // MARK: - 调度

    static func scheduleAppRefresh(after interval: TimeInterval = 60 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 每天固定时间生成当日简报。
    static func scheduleDailyBrief(hour: Int = 8, minute: Int = 0) {
        let request = BGProcessingTaskRequest(identifier: briefIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = nextOccurrence(hour: hour, minute: minute)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: briefIdentifier)
    }

    static func nextOccurrence(hour: Int, minute: Int, from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        let candidate = calendar.date(from: components) ?? date.addingTimeInterval(3_600)
        if candidate <= date {
            return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86_400)
        }
        return candidate
    }

    // MARK: - 处理

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        // BGTask 本身不是 Sendable，但它只在主线程被操作；
        // 这里显式标注以避免把整个调度器标记成非隔离。
        nonisolated(unsafe) let backgroundTask = task
        let work = Task {
            await DailyBriefService.refreshInBackground()
        }
        backgroundTask.expirationHandler = {
            work.cancel()
        }
        Task {
            await work.value
            backgroundTask.setTaskCompleted(success: !work.isCancelled)
        }
    }

    private static func handleDailyBrief(_ task: BGProcessingTask) {
        scheduleDailyBrief()
        nonisolated(unsafe) let backgroundTask = task
        let work = Task {
            await DailyBriefService.generateBrief()
        }
        backgroundTask.expirationHandler = {
            work.cancel()
        }
        Task {
            let succeeded = await work.value
            backgroundTask.setTaskCompleted(success: succeeded)
        }
    }
}

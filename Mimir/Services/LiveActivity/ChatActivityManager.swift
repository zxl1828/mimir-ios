import Foundation
import ActivityKit

/// 锁屏 / 灵动岛实时活动管理。
@MainActor
enum ChatActivityManager {

    private static var current: Activity<ChatActivityAttributes>?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(
        conversationID: String,
        title: String,
        status: String,
        preview: String,
        enabled: Bool
    ) {
        guard enabled, isSupported else { return }
        Task {
            // 复用已经存在的活动（常驻 Spark 或上一轮对话），不再先 `endAll()`。
            // 老实现每次生成都把所有活动杀一遍，包括常驻待命态——于是用户经常看到
            // 灵动岛"忽然什么都不显示"，而 ProgressCenter 的更新又找不到活动可写。
            if let first = Activity<ChatActivityAttributes>.activities.first {
                current = first
                var state = first.content.state
                state.conversationTitle = title
                state.statusText = status
                state.previewText = preview
                state.isGenerating = true
                state.startedAt = Date()
                state.updatedAt = Date()
                await apply(state)
                return
            }
            let attributes = ChatActivityAttributes(conversationID: conversationID)
            let state = ChatActivityAttributes.ContentState(
                conversationTitle: title,
                statusText: status,
                previewText: preview,
                isGenerating: true,
                tokenCount: 0,
                startedAt: Date()
            )
            do {
                current = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                current = nil
            }
        }
    }

    // MARK: - 内部

    /// 把同一份状态写到所有现存活动上。
    ///
    /// 刻意"每次重新取静态列表再遍历"，而不是握着一个抓到的 `Activity` 实例去 `update`：
    /// Swift 6 严格并发下，把已经存进静态属性的实例再跨 `await` 送出去会被判定为
    /// "sending 'existing' risks causing data races"。状态本身是 `Sendable` 值类型，
    /// 每轮从列表里新取的实例各属独立区域，所以安全。
    private static func apply(_ state: ChatActivityAttributes.ContentState) async {
        for item in Activity<ChatActivityAttributes>.activities {
            await item.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func update(
        status: String,
        preview: String,
        isGenerating: Bool,
        tokenCount: Int
    ) {
        guard let activity = current else { return }
        Task {
            var state = activity.content.state
            state.statusText = status
            state.previewText = String(preview.suffix(120))
            state.isGenerating = isGenerating
            state.tokenCount = tokenCount
            state.updatedAt = Date()
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func end(status: String, preview: String) {
        guard let activity = current else { return }
        current = nil
        Task {
            var state = activity.content.state
            state.statusText = status
            state.previewText = String(preview.suffix(120))
            state.isGenerating = false
            state.updatedAt = Date()
            if state.isResident {
                // 常驻待命态只更新内容，绝不能 end——它要一直挂在锁屏/灵动岛上。
                await activity.update(.init(state: state, staleDate: nil))
            } else {
                await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 20))
            }
        }
    }

    static func endAll() async {
        for activity in Activity<ChatActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        current = nil
    }

    // MARK: - Task 4: Cyber-Owl Live Activity & Timestamp Pin (Background Audio)

    private static var audioActivity: Activity<MimirActivityAttributes>?

    static func startAudioActivity(
        sessionID: String,
        title: String = "Mimir 实时录音",
        status: String = "正在全双工收听",
        enabled: Bool = true
    ) {
        guard enabled, isSupported else { return }
        Task {
            let attributes = MimirActivityAttributes(sessionID: sessionID)
            let state = MimirActivityAttributes.ContentState(
                conversationTitle: title,
                statusText: status,
                isAudioActive: true,
                audioElapsedSeconds: 0,
                audioLevels: [0.35, 0.75, 0.45]
            )
            do {
                audioActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                audioActivity = nil
            }
        }
    }

    static func updateAudioActivity(
        elapsedSeconds: Int,
        levels: [Float],
        status: String? = nil
    ) {
        guard let activity = audioActivity else { return }
        Task {
            var state = activity.content.state
            state.audioElapsedSeconds = elapsedSeconds
            state.audioLevels = levels
            if let status { state.statusText = status }
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func endAudioActivity() {
        guard let activity = audioActivity else { return }
        audioActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

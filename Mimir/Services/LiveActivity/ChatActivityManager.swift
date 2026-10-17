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
            await endAll()
            let attributes = ChatActivityAttributes(conversationID: conversationID)
            let state = ChatActivityAttributes.ContentState(
                conversationTitle: title,
                statusText: status,
                previewText: preview,
                isGenerating: true,
                tokenCount: 0
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

    static func update(
        status: String,
        preview: String,
        isGenerating: Bool,
        tokenCount: Int
    ) {
        guard let activity = current else { return }
        Task {
            let state = ChatActivityAttributes.ContentState(
                conversationTitle: activity.content.state.conversationTitle,
                statusText: status,
                previewText: String(preview.suffix(120)),
                isGenerating: isGenerating,
                tokenCount: tokenCount
            )
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func end(status: String, preview: String) {
        guard let activity = current else { return }
        current = nil
        Task {
            let state = ChatActivityAttributes.ContentState(
                conversationTitle: activity.content.state.conversationTitle,
                statusText: status,
                previewText: String(preview.suffix(120)),
                isGenerating: false,
                tokenCount: activity.content.state.tokenCount
            )
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 20))
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

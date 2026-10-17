import Foundation
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 锁屏与灵动岛上的 "Pin Moment"（标记高光时刻）免解锁快速意图。
public struct PinMomentIntent: AppIntent {
    public static var title: LocalizedStringResource { "Pin Moment" }
    public static var description: IntentDescription? { IntentDescription("在锁屏或灵动岛实时标记关键语音时间戳") }
    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Session ID")
    public var sessionID: String

    public init() {
        self.sessionID = ""
    }

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public func perform() async throws -> some IntentResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        let userDefaults = UserDefaults(suiteName: "group.com.zxl.mimir") ?? UserDefaults.standard
        let storageKey = "pinned_moments_\(sessionID)"
        var list = userDefaults.stringArray(forKey: storageKey) ?? []
        list.append(timestamp)
        userDefaults.set(list, forKey: storageKey)

        #if canImport(ActivityKit)
        for activity in Activity<MimirActivityAttributes>.activities {
            if activity.attributes.sessionID == sessionID || sessionID.isEmpty {
                var newState = activity.content.state
                newState.pinnedMomentsCount = list.count
                newState.lastPinnedTimestamp = timestamp
                await activity.update(.init(state: newState, staleDate: nil))
            }
        }
        #endif

        return .result()
    }
}

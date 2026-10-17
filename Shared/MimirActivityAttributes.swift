import Foundation
import ActivityKit

/// Mimir 灵动岛与锁屏实时活动共享属性（App 与 Extension 均可访问）。
public struct MimirActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        public var conversationTitle: String
        public var statusText: String
        public var isAudioActive: Bool
        public var audioElapsedSeconds: Int
        public var audioLevels: [Float] // 3 条波形柱振幅 (0.0 ~ 1.0)
        public var pinnedMomentsCount: Int
        public var lastPinnedTimestamp: String
        public var owlGlow: Double
        public var isGenerating: Bool
        public var previewText: String
        public var tokenCount: Int
        public var updatedAt: Date

        // 兼容原 Gemini Spark
        public var ambientWeather: String = ""
        public var ambientSchedule: String = ""
        public var isResident: Bool = false

        public init(
            conversationTitle: String = "Mimir 实时语音",
            statusText: String = "正在全双工收听",
            isAudioActive: Bool = true,
            audioElapsedSeconds: Int = 0,
            audioLevels: [Float] = [0.35, 0.75, 0.45],
            pinnedMomentsCount: Int = 0,
            lastPinnedTimestamp: String = "",
            owlGlow: Double = 0.65,
            isGenerating: Bool = false,
            previewText: String = "",
            tokenCount: Int = 0,
            updatedAt: Date = Date(),
            ambientWeather: String = "",
            ambientSchedule: String = "",
            isResident: Bool = false
        ) {
            self.conversationTitle = conversationTitle
            self.statusText = statusText
            self.isAudioActive = isAudioActive
            self.audioElapsedSeconds = audioElapsedSeconds
            self.audioLevels = audioLevels
            self.pinnedMomentsCount = pinnedMomentsCount
            self.lastPinnedTimestamp = lastPinnedTimestamp
            self.owlGlow = owlGlow
            self.isGenerating = isGenerating
            self.previewText = previewText
            self.tokenCount = tokenCount
            self.updatedAt = updatedAt
            self.ambientWeather = ambientWeather
            self.ambientSchedule = ambientSchedule
            self.isResident = isResident
        }
    }

    public var sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

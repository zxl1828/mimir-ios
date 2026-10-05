import Foundation
import ActivityKit

/// 对话实时活动的共享数据结构（App 与小组件扩展共用）。
struct ChatActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var conversationTitle: String
        var statusText: String
        var previewText: String
        var isGenerating: Bool
        var tokenCount: Int
        var updatedAt: Date

        // MARK: - Gemini Spark（常驻微助手）

        /// 展开态顶部上下文栏用的天气快照，例如 "🌤 24°C"。
        var ambientWeather: String = ""
        /// 展开态顶部上下文栏用的日程快照，例如 "15:30 会议"。
        var ambientSchedule: String = ""
        /// 猫头鹰呼吸光晕强度（0...1），由 App 侧按周期推进，让常驻态看起来"活着"。
        var owlGlow: Double = 0.6
        /// 是否为常驻待命态（区别于一次性的对话活动）。
        var isResident: Bool = false

        public init(
            conversationTitle: String,
            statusText: String,
            previewText: String,
            isGenerating: Bool,
            tokenCount: Int,
            updatedAt: Date = Date(),
            ambientWeather: String = "",
            ambientSchedule: String = "",
            owlGlow: Double = 0.6,
            isResident: Bool = false
        ) {
            self.conversationTitle = conversationTitle
            self.statusText = statusText
            self.previewText = previewText
            self.isGenerating = isGenerating
            self.tokenCount = tokenCount
            self.updatedAt = updatedAt
            self.ambientWeather = ambientWeather
            self.ambientSchedule = ambientSchedule
            self.owlGlow = owlGlow
            self.isResident = isResident
        }
    }

    var conversationID: String

    init(conversationID: String) {
        self.conversationID = conversationID
    }
}

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

        // MARK: - 运行中进展（对照手机端 harness 的展开态灵动岛）

        /// 用户这句需求的短标题，展开态第一行大号粗体，例如「读取记忆库了解项目进展」。
        var taskTitle: String = ""
        /// 正在做的事，例如「准备调用 compress」。
        var toolDetail: String = ""
        /// 正在调用的工具名（可能为空）。
        var toolName: String = ""
        /// 第几步（0 表示还没有具体步骤）。
        var progressStep: Int = 0
        /// 一共有多少步（0 表示未知，此时只显示"第 N 步"）。
        var progressTotal: Int = 0
        /// 工具往返轮数。
        var rounds: Int = 0
        /// 本轮开始时间；Widget 用 `Text(_, style: .timer)` 自己走秒，不依赖 App 推送。
        var startedAt: Date = Date()
        /// 底部一行小字：设备 · 工作区。
        var workspaceName: String = ""

        /// 「第 N 步」的展示文本；没有步数时退回状态文案。
        var stepLabel: String {
            if progressStep > 0 {
                return progressTotal > 0 ? "第 \(progressStep)/\(progressTotal) 步" : "第 \(progressStep) 步"
            }
            return statusText
        }

        /// 展开态中部那一行：优先显示具体动作，其次回落到状态。
        var activityLine: String {
            if !toolDetail.isEmpty { return toolDetail }
            if !statusText.isEmpty { return statusText }
            return isGenerating ? "正在处理…" : "待命中"
        }

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
            isResident: Bool = false,
            taskTitle: String = "",
            toolDetail: String = "",
            toolName: String = "",
            progressStep: Int = 0,
            progressTotal: Int = 0,
            rounds: Int = 0,
            startedAt: Date = Date(),
            workspaceName: String = ""
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
            self.taskTitle = taskTitle
            self.toolDetail = toolDetail
            self.toolName = toolName
            self.progressStep = progressStep
            self.progressTotal = progressTotal
            self.rounds = rounds
            self.startedAt = startedAt
            self.workspaceName = workspaceName
        }
    }

    var conversationID: String

    init(conversationID: String) {
        self.conversationID = conversationID
    }
}

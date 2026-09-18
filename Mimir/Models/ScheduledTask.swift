import Foundation
import SwiftData

/// 用户自定义的定时任务：到点后用指定智能体与技能生成内容，
/// 结果自动存成一段新对话。
@Model
final class ScheduledTask {
    var id: UUID = UUID()
    var title: String = ""
    /// 每次执行时发送给模型的内容。
    var prompt: String = ""
    var agentName: String = ""
    var skillName: String = ""
    var thinkingModeRaw: String = ThinkingMode.thinking.rawValue
    var hour: Int = 8
    var minute: Int = 0
    /// 星期位掩码：bit0 = 周日，bit6 = 周六。127 表示每天。
    var weekdayMask: Int = 127
    var isEnabled: Bool = false
    var lastRunAt: Date?
    var lastResultConversationID: UUID?
    var lastError: String = ""
    var runCount: Int = 0
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        agentName: String = "",
        skillName: String = "",
        thinkingMode: ThinkingMode = .thinking,
        hour: Int = 8,
        minute: Int = 0,
        weekdayMask: Int = 127,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.agentName = agentName
        self.skillName = skillName
        self.thinkingModeRaw = thinkingMode.rawValue
        self.hour = hour
        self.minute = minute
        self.weekdayMask = weekdayMask
        self.isEnabled = isEnabled
    }
}

extension ScheduledTask {

    static let everydayMask = 0b1111111
    static let weekdayOnlyMask = 0b0111110
    static let weekendMask = 0b1000001

    var thinkingMode: ThinkingMode {
        get { ThinkingMode(rawValue: thinkingModeRaw) ?? .thinking }
        set { thinkingModeRaw = newValue.rawValue }
    }

    /// 人类可读的调度描述，例如「每天 08:00」。
    var scheduleDescription: String {
        let time = String(format: "%02d:%02d", hour, minute)
        if weekdayMask == Self.everydayMask { return "每天 \(time)" }
        if weekdayMask == Self.weekdayOnlyMask { return "工作日 \(time)" }
        if weekdayMask == Self.weekendMask { return "周末 \(time)" }

        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let days = (0..<7)
            .filter { weekdayMask & (1 << $0) != 0 }
            .map { "周" + names[$0] }
        guard !days.isEmpty else { return "未选择日期" }
        return days.joined(separator: "、") + " " + time
    }

    /// 下一次触发时间。
    func nextFireDate(after date: Date = Date()) -> Date? {
        guard isEnabled, weekdayMask != 0 else { return nil }
        let calendar = Calendar.current

        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components), candidate > date else { continue }

            let weekday = calendar.component(.weekday, from: candidate) // 1 = 周日
            if weekdayMask & (1 << (weekday - 1)) != 0 {
                return candidate
            }
        }
        return nil
    }

    /// 今天该跑的时间点是否已过、且今天还没跑过。
    func isDue(at date: Date = Date()) -> Bool {
        guard isEnabled, weekdayMask != 0 else { return false }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard weekdayMask & (1 << (weekday - 1)) != 0 else { return false }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let scheduled = calendar.date(from: components), date >= scheduled else { return false }

        if let last = lastRunAt, last >= scheduled { return false }
        return true
    }
}

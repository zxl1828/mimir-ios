import ActivityKit
import Foundation
import Observation

/// Gemini Spark 范式：让助手以「常驻微代理」的形态活在硬件灵动岛上。
///
/// 与 `ChatActivityManager` 的分工：
/// - `ChatActivityManager` 负责**一次对话**的实时活动（生成中 → 完成 → 自动消失）
/// - 本控制器负责**常驻待命态**：App 启动即请求一条不会过期的活动
///   （`staleDate: nil`），并维护环境上下文快照与猫头鹰呼吸光晕
///
/// 之所以复用 `ChatActivityAttributes` 而不新建一套 Attributes：Widget 扩展里
/// 只应该存在一个 `ActivityConfiguration`，两套并行会让灵动岛出现互相抢占的活动。
@MainActor
@Observable
final class MimirSparkManager {

    static let shared = MimirSparkManager()

    // MARK: - 可观察状态

    private(set) var isResident = false
    private(set) var ambientWeather = ""
    private(set) var ambientSchedule = ""
    private(set) var lastPreviewText = ""
    private(set) var lastStatusText = "Mimir 待命"

    // MARK: - 内部

    private var activity: Activity<ChatActivityAttributes>?
    private var glowTask: Task<Void, Never>?
    /// 呼吸光晕当前值（0.35 ~ 0.85 往复）。
    private var glowPhase: Double = 0.6
    /// 常驻活动的固定标识，便于识别与去重。
    private let residentID = "mimir.spark.resident"

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - 常驻生命周期

    /// App 启动 / 回到前台时调用：确保常驻灵动岛存在。
    ///
    /// 已经有一条活动时直接复用，不会重复请求；系统未授权实时活动时静默跳过。
    func bootstrap() async {
        guard isSupported else { return }

        if let existing = Activity<ChatActivityAttributes>.activities.first {
            activity = existing
            isResident = true
            startGlowLoop()
            return
        }

        let attributes = ChatActivityAttributes(conversationID: residentID)
        let state = makeState(status: "待命", preview: "", generating: false)
        do {
            // staleDate 传 nil：系统不会自动过期或收起，这是"常驻"的关键。
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            isResident = true
            startGlowLoop()
        } catch {
            activity = nil
            isResident = false
        }
    }

    /// 回到前台时的轻量检查：常驻断了就重建。
    func resumeIfNeeded() async {
        guard !isResident else { return }
        await bootstrap()
    }

    /// 结束常驻（用户在设置里关闭，或需要让位给一次性对话活动时）。
    func endResidency() async {
        glowTask?.cancel()
        glowTask = nil
        for item in Activity<ChatActivityAttributes>.activities {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        isResident = false
    }

    // MARK: - 内容更新

    /// 更新环境上下文快照（时间 / 天气 / 日程），显示在展开态顶部。
    func updateAmbient(weather: String, schedule: String) {
        ambientWeather = weather
        ambientSchedule = schedule
        push(status: lastStatusText, preview: lastPreviewText, generating: false)
    }

    /// 推送助手回复的短文本（展开态展示 2~4 行）。
    func pushResponse(_ text: String, isGenerating: Bool) {
        lastPreviewText = text
        push(
            status: isGenerating ? "生成中" : "已完成",
            preview: text,
            generating: isGenerating
        )
    }

    /// 回到待命态；调用方负责 3 秒后触发（自动折叠）。
    func collapse() {
        push(status: "Mimir 待命", preview: lastPreviewText, generating: false)
    }

    // MARK: - 内部

    private func makeState(
        status: String,
        preview: String,
        generating: Bool
    ) -> ChatActivityAttributes.ContentState {
        lastStatusText = status
        return ChatActivityAttributes.ContentState(
            conversationTitle: "Mimir",
            statusText: status,
            previewText: String(preview.suffix(160)),
            isGenerating: generating,
            tokenCount: 0,
            ambientWeather: ambientWeather,
            ambientSchedule: ambientSchedule,
            owlGlow: glowPhase,
            isResident: true
        )
    }

    private func push(status: String, preview: String, generating: Bool) {
        guard let activity else { return }
        let state = makeState(status: status, preview: preview, generating: generating)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// 呼吸光晕：与 App 内 `MimirMascot` 的呼吸节奏保持一致——**全周期 2.2 秒**，
    /// 在 0.35 与 0.85 之间往复（半周期 1.1 秒，规范书写的 3 秒与 App 原有动效不符，
    /// 按"动画要符合原 App"的要求对齐到 2.2 秒）。
    ///
    /// 只在 App 存活期间推进——进程被系统回收后，灵动岛会停在最后一帧
    /// （这是 Live Activity 的固有限制，无法在进程外驱动动画）。
    private func startGlowLoop() {
        guard glowTask == nil else { return }
        glowTask = Task { [weak self] in
            var rising = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1_100))
                guard let self else { return }
                self.glowPhase = rising ? 0.85 : 0.35
                rising.toggle()
                self.push(
                    status: self.lastStatusText,
                    preview: self.lastPreviewText,
                    generating: false
                )
            }
        }
    }
}

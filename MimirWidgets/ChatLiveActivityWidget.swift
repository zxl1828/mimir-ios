import ActivityKit
import SwiftUI
import WidgetKit

/// Spark 主题色（与 App 内 AppUI.brandPurple 保持一致；Widget 扩展不能引用 App 目标代码，
/// 所以这里保留一份数值副本）。
private let sparkViolet = Color(red: 0.52, green: 0.36, blue: 0.95)
/// 深色基准（#120D1D），锁屏卡片底色。
private let sparkPlum = Color(red: 0.07, green: 0.05, blue: 0.11)

/// 锁屏与灵动岛上的 Mimir Spark 常驻状态。
///
/// 三态展示：
/// - 常驻（compact）：猫头鹰矢量 + 主题色呼吸光晕 / 右侧状态点
/// - 极简（minimal）：静态猫头鹰 + 光晕
/// - 展开（expanded）：上下文栏（状态 + 天气 + 日程）+ 响应文本 + 输入入口胶囊
///
/// 注意：Live Activity **不支持文本输入控件**（系统限制），所以底部"输入胶囊"
/// 做成唤起 App 输入框的入口（`widgetURL`），点击会带着 mimir://spark 打开主应用。
struct ChatLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatActivityAttributes.self) { context in
            LockScreenSparkView(state: context.state)
                .activityBackgroundTint(sparkPlum.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "mimir://spark"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        owlGlyph(glow: context.state.owlGlow)
                        Text("Mimir")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    runningPill(context.state)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    expandedProgress(context.state)
                }
            } compactLeading: {
                owlGlyph(glow: context.state.owlGlow)
            } compactTrailing: {
                compactStatus(context.state)
            } minimal: {
                owlGlyph(glow: 0.7)
            }
            .keylineTint(sparkViolet)
            .widgetURL(URL(string: "mimir://spark"))
        }
    }

    // MARK: - 常驻态部件

    /// 猫头鹰微矢量 + 主题色光晕；glow 由 App 侧按周期推进（0.35 ~ 0.85）。
    private func owlGlyph(glow: Double) -> some View {
        Image(systemName: "bird.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(sparkViolet)
            .shadow(color: sparkViolet.opacity(min(max(glow, 0.35), 0.85)), radius: 6)
    }

    /// 动态岛紧凑态右侧：执行中报步数，结束显示完成勾。
    @ViewBuilder
    private func compactStatus(_ state: ChatActivityAttributes.ContentState) -> some View {
        if state.isGenerating {
            if state.progressStep > 0 {
                Text("\(state.progressStep)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sparkViolet)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sparkViolet)
            }
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(sparkViolet.opacity(0.9))
        }
    }

    // MARK: - 展开态：运行中进展

    /// 右上角胶囊：`↑ 执行中 2:08`。计时由系统 `Text(_, style: .timer)` 自己走秒，
    /// App 完全不用为"秒数在跳"推送更新（Live Activity 的更新预算很紧）。
    private func runningPill(_ state: ChatActivityAttributes.ContentState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: state.isGenerating ? "arrow.up" : "checkmark")
                .font(.system(size: 9, weight: .bold))
            if state.isGenerating {
                Text(state.startedAt, style: .timer)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            } else {
                Text(state.statusText.isEmpty ? "已完成" : state.statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.white.opacity(0.94))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.14)))
    }

    /// 展开态主体：标题 / 正在调用的动作 / 第几步 + 进度条 / 分隔线 / 设备·工作区。
    private func expandedProgress(_ state: ChatActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline(state))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("详情")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            HStack(spacing: 5) {
                Image(systemName: progressGlyph(for: state.toolName))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(sparkViolet)
                Text(state.activityLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(state.stepLabel)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
                if state.progressTotal > 0 {
                    progressTrack(state).frame(maxWidth: 90)
                }
                Spacer(minLength: 0)
                if state.rounds > 0 {
                    Text("\(state.rounds) 轮")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.40))
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.6)

            Text(state.workspaceName.isEmpty ? "本机 · Mimir" : state.workspaceName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.40))
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headline(_ state: ChatActivityAttributes.ContentState) -> String {
        let title = state.taskTitle.isEmpty ? state.conversationTitle : state.taskTitle
        return title.isEmpty ? "正在处理" : title
    }
}

// MARK: - 共用部件（灵动岛与锁屏都要用，所以放在文件作用域）

/// 工具名 → 图标：尽量给"正在做什么"一个形状，而不是清一色扳手。
private func progressGlyph(for name: String) -> String {
    switch name {
    case "compress", "context": return "arrow.down.right.and.arrow.up.left"
    case "search", "web_search", "search_context": return "magnifyingglass"
    case "todo_write", "task": return "checklist"
    case "read", "read_file": return "doc.text"
    case "write", "edit": return "square.and.pencil"
    case "pwsh", "bash", "shell": return "terminal"
    case "": return "wrench.and.screwdriver.fill"
    default: return "hammer.fill"
    }
}

private func progressTrack(_ state: ChatActivityAttributes.ContentState) -> some View {
    let total = max(state.progressTotal, 1)
    let ratio = min(max(Double(state.progressStep) / Double(total), 0.02), 1)
    return GeometryReader { proxy in
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.12))
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(sparkViolet)
                .frame(width: max(proxy.size.width * ratio, 3))
        }
    }
    .frame(height: 3)
}


// MARK: - 锁屏视图

private struct LockScreenSparkView: View {

    let state: ChatActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(sparkViolet.opacity(0.20))
                        .frame(width: 38, height: 38)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        .frame(width: 38, height: 38)
                    Image(systemName: "bird.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: sparkViolet.opacity(min(max(state.owlGlow, 0.35), 0.85)), radius: 8)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Mimir")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Circle()
                            .fill(state.isGenerating ? Color.green : sparkViolet)
                            .frame(width: 5, height: 5)
                        Text(state.isGenerating ? "正在思考" : (state.statusText.isEmpty ? "随时响应" : state.statusText.replacingOccurrences(of: "Mimir ", with: "")))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(1)
                    }
                    Text(state.taskTitle.isEmpty ? (state.conversationTitle.isEmpty ? "AI 助手" : state.conversationTitle) : state.taskTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                Image(systemName: state.isGenerating ? "waveform" : "waveform.circle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(sparkViolet.opacity(0.95))
            }

            if state.isGenerating || state.progressStep > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: progressGlyph(for: state.toolName))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(sparkViolet)
                        Text(state.activityLine)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(state.stepLabel)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .lineLimit(1)
                    }
                    if state.progressTotal > 0 {
                        progressTrack(state)
                    }
                }
            }

            Text(state.previewText.isEmpty ? "轻点打开 Mimir，继续你的对话。" : state.previewText)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(state.previewText.isEmpty ? 0.68 : 0.92))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                Text(state.isGenerating ? "LIVE RESPONSE" : "TAP TO CONTINUE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if state.tokenCount > 0 {
                    Text("\(state.tokenCount) TOKENS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
            .foregroundStyle(Color.white.opacity(0.84))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.13, blue: 0.31),
                            Color(red: 0.11, green: 0.08, blue: 0.17),
                            Color(red: 0.08, green: 0.06, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.20), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.36), sparkViolet.opacity(0.40), Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: sparkViolet.opacity(0.18), radius: 18, y: 8)
    }
}

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
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        owlGlyph(glow: context.state.owlGlow)
                        Text(context.state.statusText.isEmpty ? "Mimir" : context.state.statusText)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ambientSnapshot(context.state)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    expandedStage(context.state)
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

    @ViewBuilder
    private func compactStatus(_ state: ChatActivityAttributes.ContentState) -> some View {
        if state.isGenerating {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sparkViolet)
        } else {
            Circle()
                .fill(sparkViolet.opacity(0.85))
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - 展开态部件

    private func ambientSnapshot(_ state: ChatActivityAttributes.ContentState) -> some View {
        HStack(spacing: 5) {
            if !state.ambientWeather.isEmpty {
                Text(state.ambientWeather)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                // 天气尚未接入时退化为本地时间（Widget 的 Text 会自动走时，无需 App 推送）
                Text(Date(), style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !state.ambientSchedule.isEmpty {
                Text("📅 " + state.ambientSchedule)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func expandedStage(_ state: ChatActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 响应文本：高信噪比的 2~4 行
            Text(state.previewText.isEmpty ? "随时说点什么，我会在这里回应。" : state.previewText)
                .font(.system(size: 12))
                .foregroundStyle(state.previewText.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 输入入口：Live Activity 不支持输入控件，点按唤起 App 输入框
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("点按输入")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(sparkViolet.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

// MARK: - 锁屏视图

private struct LockScreenSparkView: View {

    let state: ChatActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bird.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(sparkViolet)
                .shadow(color: sparkViolet.opacity(min(max(state.owlGlow, 0.35), 0.85)), radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.statusText.isEmpty ? "Mimir 待命" : state.statusText)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if !state.ambientWeather.isEmpty || !state.ambientSchedule.isEmpty {
                    Text([state.ambientWeather, state.ambientSchedule]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !state.previewText.isEmpty {
                    Text(state.previewText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if state.isGenerating {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(14)
    }
}

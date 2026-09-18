import ActivityKit
import WidgetKit
import SwiftUI

/// 锁屏与灵动岛上的对话状态。
struct ChatLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChatActivityAttributes.self) { context in
            LockScreenChatView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.isGenerating ? "生成中" : "已完成")
                            .font(.system(size: 12, weight: .semibold))
                    } icon: {
                        Image(systemName: context.state.isGenerating ? "sparkles" : "checkmark.circle")
                            .foregroundStyle(.tint)
                    }
                    .labelStyle(.titleAndIcon)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.tokenCount) tokens")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.conversationTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.previewText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.isGenerating ? "sparkles" : "checkmark.circle")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.isGenerating ? "…" : "✓")
                    .font(.system(size: 13, weight: .semibold))
            } minimal: {
                Image(systemName: context.state.isGenerating ? "sparkles" : "checkmark.circle")
                    .foregroundStyle(.tint)
            }
            .keylineTint(.blue)
        }
    }
}

private struct LockScreenChatView: View {

    let state: ChatActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.isGenerating ? "sparkles" : "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(state.isGenerating ? Color.blue : Color.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.conversationTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(state.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

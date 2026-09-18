import SwiftUI

/// MCP 工具调用的实时进度条。
struct ToolProgressView: View {

    let calls: [MCPClientManager.ToolCallProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(calls) { call in
                HStack(spacing: 9) {
                    icon(for: call.phase)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(call.serverName) · \(call.toolName)")
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(1)
                        Text(call.detail)
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if case .running = call.phase {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColor.secondaryText.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 6)
        .transition(.opacity)
    }

    @ViewBuilder
    private func icon(for phase: MCPClientManager.ToolCallProgress.Phase) -> some View {
        switch phase {
        case .running:
            Image(systemName: "gearshape.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.brandIndigo)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.danger)
        }
    }
}

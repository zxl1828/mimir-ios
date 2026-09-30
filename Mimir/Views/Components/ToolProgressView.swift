import SwiftUI

/// MCP 工具调用的实时进度条（Codex 沙盒工具胶囊风格）。
struct ToolProgressView: View {

    let calls: [MCPClientManager.ToolCallProgress]

    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(calls) { call in
                HStack(spacing: 10) {
                    icon(for: call.phase)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("MCP Skill: \(call.serverName) · \(call.toolName)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppUI.label)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(call.detail.isEmpty ? "Sandboxed" : call.detail)
                                .font(AppUI.caption)
                                .foregroundStyle(AppUI.label2)
                                .lineLimit(1)

                            Circle()
                                .fill(Color(red: 0.24, green: 0.82, blue: 0.38))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(Color(red: 1.00, green: 0.68, blue: 0.20))
                                .frame(width: 6, height: 6)
                        }
                    }

                    Spacer(minLength: 4)

                    if case .running = call.phase {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .liquidGlass(cornerRadius: 14, glowIntensity: 0.2)
            }
        }
        .padding(.horizontal, 6)
        .transition(.opacity)
    }

    @ViewBuilder
    private func icon(for phase: MCPClientManager.ToolCallProgress.Phase) -> some View {
        switch phase {
        case .running:
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.42))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.96, green: 0.30, blue: 0.33))
        }
    }
}

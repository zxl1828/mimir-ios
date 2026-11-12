import SwiftUI

/// 对话页里的「任务」卡片。
///
/// 对应 DSH 客户端那张折叠卡：标题行写着「任务 · 1 进行中 · 7 待处理」，
/// 点开逐条列出步骤与状态。数据来自 `TaskBoardStore`，由模型的 `update_plan` 工具喂进来。
struct TaskBoardCard: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    @State private var store = TaskBoardStore.shared
    @State private var expanded = false

    var body: some View {
        if !store.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Haptics.selectionChanged()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("任务")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppUI.label)
                            Text(store.summaryLine)
                                .font(AppUI.mono(10.5, weight: .regular))
                                .foregroundStyle(AppUI.label2)
                        }

                        Spacer(minLength: 6)

                        Text("\(store.completedCount)/\(store.total)")
                            .font(AppUI.mono(10.5, weight: .medium))
                            .foregroundStyle(AppUI.label3)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppUI.label3)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(StaticButtonFeedbackStyle())

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.items) { item in
                            HStack(alignment: .top, spacing: 8) {
                                statusGlyph(item.status)
                                    .frame(width: 14, height: 14)
                                    .padding(.top, 1)

                                Text(item.title)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(item.status == .completed ? AppUI.label3 : AppUI.label2)
                                    .strikethrough(item.status == .completed, color: AppUI.label3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .nativeGlassRect(cornerRadius: 18, interactive: false)
        }
    }

    @ViewBuilder
    private func statusGlyph(_ status: TaskBoardStore.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(accent.opacity(0.85))
        case .inProgress:
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .overlay {
                    Circle().fill(accent).frame(width: 3.5, height: 3.5)
                }
        case .pending:
            Circle()
                .strokeBorder(AppUI.label3.opacity(0.65), lineWidth: 1.4)
        }
    }
}

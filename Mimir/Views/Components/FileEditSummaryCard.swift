import SwiftUI

/// 消息流结尾的文件编辑统计卡片。
///
/// 顶部一行「已编辑 X 个文件」+ 绿色 `+N` / 红色 `-M`，点按展开后列出本轮改过的每个文件路径
/// 及其各自的增删行数。数据来自 `FileEditLedger`，只有真的落过盘才会出现——没有编辑就完全不占位。
struct FileEditSummaryCard: View {

    /// 对应助手消息 id（也就是一次生成轮次）。
    let runID: UUID

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @State private var ledger = FileEditLedger.shared
    @State private var expanded = false

    private let addedColor = Color(red: 0.22, green: 0.72, blue: 0.42)
    private let removedColor = Color(red: 0.90, green: 0.34, blue: 0.34)

    var body: some View {
        let edits = ledger.edits(for: runID)
        if !edits.isEmpty {
            let totals = ledger.totals(for: runID)
            VStack(alignment: .leading, spacing: 0) {
                header(totals)
                if expanded {
                    Divider()
                        .overlay(AppUI.consoleHairline(scheme: scheme))
                        .padding(.horizontal, 12)
                    fileList(edits)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppUI.consolePanel(scheme: scheme).opacity(scheme == .dark ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 0.5)
            )
        }
    }

    private func header(_ totals: (files: Int, added: Int, removed: Int)) -> some View {
        Button {
            Haptics.impact(.light)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)

                Text("已编辑 \(totals.files) 个文件")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppUI.label)

                Spacer(minLength: 6)

                Text("+\(totals.added)")
                    .font(AppUI.mono(11, weight: .semibold))
                    .foregroundStyle(addedColor)

                Text("-\(totals.removed)")
                    .font(AppUI.mono(11, weight: .semibold))
                    .foregroundStyle(removedColor)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppUI.label3)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileList(_ edits: [FileEditLedger.Edit]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(edits) { edit in
                HStack(spacing: 8) {
                    Text(edit.path)
                        .font(AppUI.mono(10.5))
                        .foregroundStyle(AppUI.label2)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 6)

                    if edit.added > 0 {
                        Text("+\(edit.added)")
                            .font(AppUI.mono(10.5, weight: .semibold))
                            .foregroundStyle(addedColor)
                    }
                    if edit.removed > 0 {
                        Text("-\(edit.removed)")
                            .font(AppUI.mono(10.5, weight: .semibold))
                            .foregroundStyle(removedColor)
                    }
                }
            }
        }
        .padding(.top, 9)
    }
}

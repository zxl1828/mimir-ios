import SwiftUI
import UIKit

/// 斜杠命令唤起的技能选择浮层。
///
/// 出现在输入框上方，不占用布局高度；键盘保持打开，输入焦点不移动。
struct SkillPicker: View {

    let skills: [Skill]
    let query: String
    let highlightedIndex: Int
    var onHighlight: (Int) -> Void
    var onSelect: (Skill) -> Void
    var onDismiss: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)

            if skills.isEmpty {
                emptyHint
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                                row(skill, isHighlighted: index == highlightedIndex)
                                    .id(index)
                                    .onTapGesture { onSelect(skill) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: highlightedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
                .frame(maxHeight: maxListHeight)
            }
        }
        .liquidGlass(cornerRadius: 18, glowIntensity: 0.28)
        .padding(.horizontal, 6)
        .transition(
            .asymmetric(
                insertion: .offset(y: 8).combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    private var maxListHeight: CGFloat {
        max(UIScreen.main.bounds.height * 0.4 - 96, 120)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slash.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)

            if query.isEmpty {
                Text("选择技能")
                    .font(AppUI.chip)
                    .foregroundStyle(AppUI.label2)
            } else {
                Text("/" + query)
                    .font(AppUI.chip)
                    .foregroundStyle(AppUI.label)
            }

            Spacer(minLength: 4)

            Text("↑↓ 选择 · 回车确认 · Esc 取消")
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ skill: Skill, isHighlighted: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: skill.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHighlighted ? .white : accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(isHighlighted
                                  ? AnyShapeStyle(accent)
                                  : AnyShapeStyle(accent.opacity(0.14)))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(isHighlighted ? accent : AppUI.label)
                if !skill.summary.isEmpty {
                    Text(skill.summary)
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text("/" + skill.slashCommand)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppUI.label3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? accent.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Text("没有匹配的技能")
                .font(AppUI.footnote)
                .foregroundStyle(AppUI.label2)
            Text("继续输入普通文字即可关闭，或到设置里新建技能")
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

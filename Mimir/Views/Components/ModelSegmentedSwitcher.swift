import SwiftUI

/// 顶部命令胶囊滑块（Codex 桌面端风格）。
///
/// 所有候选模型并排放在一条液态玻璃胶囊槽里，当前选中项用一枚
/// 紫色发光胶囊标出，切换时用 `matchedGeometryEffect` 平滑滑动。
/// 选项过多时整条可以横向滚动。
struct ModelSegmentedSwitcher: View {

    let options: [ModelCatalog.Option]
    @Binding var selectedID: String
    /// 长按 / 右键入口：打开模型与参数设置。
    var onOpenSettings: () -> Void = {}

    @Namespace private var pill
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    private static let pillID = "model.segment.pill"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(options) { option in
                    segment(option)
                }
            }
            .padding(2)
        }
        .scrollClipDisabled()
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 8, y: 3)
        .contextMenu {
            Button {
                onOpenSettings()
            } label: {
                Label("自定义模型与参数…", systemImage: "slider.horizontal.3")
            }
        }
        .animation(AppUI.snap, value: selectedID)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: ModelCatalog.Option) -> some View {
        let isSelected = option.id == selectedID

        return Button {
            guard !isSelected else { return }
            Haptics.selectionChanged()
            selectedID = option.id
        } label: {
            Text(ModelCatalog.shortLabel(for: option.id))
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : AppUI.label2)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .contentShape(Capsule(style: .continuous))
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(accent)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        AppUI.refractionEdge(accent, scheme: scheme),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: accent.opacity(0.55), radius: 9)
                            .matchedGeometryEffect(id: Self.pillID, in: pill)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ModelSegmentedSwitcherPreviewHost: View {

    @State private var selected = "deepseek-chat"

    var body: some View {
        ModelSegmentedSwitcher(
            options: [
                ModelCatalog.Option(id: "deepseek-chat", title: "deepseek-chat"),
                ModelCatalog.Option(id: "deepseek-reasoner", title: "deepseek-reasoner")
            ],
            selectedID: $selected
        )
        .padding(30)
    }
}

#Preview {
    ModelSegmentedSwitcherPreviewHost()
}

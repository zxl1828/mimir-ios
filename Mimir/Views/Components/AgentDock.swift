import SwiftUI
import UIKit

/// 智能体快捷栏：横向滚动的胶囊，切换当前对话的智能体上下文。
struct AgentDock: View {

    let agents: [AgentDockItem]
    @Binding var selected: AgentDockItem?
    var onManage: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(
                    title: "通用",
                    icon: "sparkles",
                    tint: AppColor.brandIndigo,
                    isSelected: selected == nil
                ) {
                    Haptics.selectionChanged()
                    withAnimation(AppAnimation.chip) { selected = nil }
                }

                ForEach(agents) { agent in
                    chip(
                        title: agent.name,
                        icon: agent.icon,
                        tint: agent.tintColor,
                        isSelected: selected?.id == agent.id
                    ) {
                        Haptics.selectionChanged()
                        withAnimation(AppAnimation.chip) { selected = agent }
                    }
                }

                Button {
                    Haptics.impact(.light)
                    onManage()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(AppColor.secondaryText.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("管理智能体")
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(
        title: String,
        icon: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(AppFont.chipCompact)
            }
            .foregroundStyle(isSelected ? .white : AppColor.secondaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(AppColor.secondaryText.opacity(0.10)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.0) : AppColor.separator.opacity(0.28), lineWidth: 0.7)
            )
            .shadow(color: isSelected ? tint.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension AgentDockItem {
    /// 胶囊配色：优先使用自定义色，否则按名称哈希挑一个品牌色。
    var tintColor: Color {
        if !accentHex.isEmpty, let parsed = Color(hex: accentHex) { return parsed }
        let palette: [Color] = [
            AppColor.brandIndigo,
            AppColor.brandTeal,
            AppColor.brandPurple,
            AppColor.brandBlue
        ]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

extension Color {
    /// 解析 `#RRGGBB` 形式的颜色。
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

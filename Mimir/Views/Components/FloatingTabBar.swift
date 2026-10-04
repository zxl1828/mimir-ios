import SwiftUI

/// 悬浮式毛玻璃底栏（Floating Glass TabBar）。
///
/// 悬浮于屏幕底部边缘上方，高度约 64pt，两端收圆弧胶囊设计。
/// 包含 4 个图标项：AI Assistant、Dashboard、Files、Code。
/// 当前选中项具备淡紫色呼吸光晕（Glow Pill）背景与微跳动量反馈。
struct FloatingTabBar: View {

    @Binding var selectedTab: AppTab
    @Namespace private var tabPillAnimation

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 64)
        .liquidGlass(.regular.interactive(), in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.40 : 0.85),
                            AppUI.electricViolet.opacity(scheme == .dark ? 0.35 : 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: AppUI.electricViolet.opacity(scheme == .dark ? 0.26 : 0.12),
            radius: 20,
            x: 0,
            y: 8
        )
        .shadow(
            color: Color.black.opacity(scheme == .dark ? 0.45 : 0.08),
            radius: 12,
            x: 0,
            y: 4
        )
        .padding(.horizontal, 20)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            if selectedTab != tab {
                Haptics.selectionChanged()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: isSelected ? 18 : 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected
                            ? AppUI.electricViolet
                            : (scheme == .dark ? Color(hex: "9CA3AF") : Color(hex: "5D5870"))
                    )
                    .scaleEffect(isSelected ? 1.06 : 1.0)

                Text(tab.title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected
                            ? AppUI.electricViolet
                            : (scheme == .dark ? Color(hex: "9CA3AF") : Color(hex: "5D5870"))
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .liquidGlass(.regular.tint(AppUI.electricViolet.opacity(0.32)).interactive(), in: .capsule)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AppUI.electricViolet.opacity(0.45), lineWidth: 0.9)
                        )
                        .shadow(color: AppUI.electricViolet.opacity(0.35), radius: 8, y: 1)
                        .matchedGeometryEffect(id: "floating.tab.glow.pill", in: tabPillAnimation)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PhysicalElasticCapsuleButtonStyle())
        .accessibilityLabel(tab.title)
    }
}

import SwiftUI

/// 悬浮式 Liquid Glass 四大金刚底栏（Floating Liquid Glass TabBar）。
///
/// 悬浮于屏幕底部边缘上方，高度 64pt，两端收圆弧胶囊设计。
/// 包含 4 个图标项：AI Assistant、Dashboard、Files、Code。
/// 当前选中项绑定动态主题色微光胶囊（Glow Pill）背景与微跳动量反馈，
/// 严格维持单色系微阶渐变（Monochromatic Harmony），严禁硬编码静态紫色。
struct FloatingTabBar: View {

    @Binding var selectedTab: AppTab
    @Namespace private var tabPillAnimation

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
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
                            Color.white.opacity(scheme == .dark ? 0.45 : 0.85),
                            accent.opacity(scheme == .dark ? 0.35 : 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: accent.opacity(scheme == .dark ? 0.28 : 0.14),
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
                            ? accent
                            : (scheme == .dark ? Color(hex: "9CA3AF") : Color(hex: "5D5870"))
                    )
                    .scaleEffect(isSelected ? 1.06 : 1.0)

                Text(tab.title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected
                            ? accent
                            : (scheme == .dark ? Color(hex: "9CA3AF") : Color(hex: "5D5870"))
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .liquidGlass(.regular.tint(accent.opacity(0.32)).interactive(), in: .capsule)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(accent.opacity(0.50), lineWidth: 1.0)
                        )
                        .shadow(color: accent.opacity(0.35), radius: 8, y: 1)
                        .matchedGeometryEffect(id: "floating.tab.glow.pill", in: tabPillAnimation)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PhysicalElasticCapsuleButtonStyle())
        .accessibilityLabel(tab.title)
    }
}

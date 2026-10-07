import SwiftUI

/// Floating command dock with an expanding active destination.
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
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .frame(height: 66)
        .background {
            Capsule(style: .continuous)
                .fill(
                    scheme == .dark
                        ? Color(hex: "241936").opacity(0.48)
                        : Color.white.opacity(0.62)
                )
        }
        .liquidGlass(.regular.tint(accent.opacity(0.08)), in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    AppUI.refractionEdge(accent, scheme: scheme),
                    lineWidth: 1.0
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.34 : 0.82),
                            Color.white.opacity(scheme == .dark ? 0.09 : 0.28),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 22)
                .padding(.horizontal, 1)
                .padding(.top, 1)
                .allowsHitTesting(false)
        }
        .shadow(
            color: accent.opacity(scheme == .dark ? 0.24 : 0.12),
            radius: 24,
            x: 0,
            y: 10
        )
        .frame(maxWidth: 480)
        .padding(.horizontal, 16)
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
            HStack(spacing: 7) {
                Image(systemName: tab.icon)
                    .font(.system(size: isSelected ? 17 : 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accent : inactiveColor)
                    .frame(width: 20)

                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                }
            }
            .frame(width: isSelected ? 88 : 48, height: 50)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.15 : 0.10))
                        .liquidGlass(.regular.tint(accent.opacity(0.18)), in: .capsule)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(scheme == .dark ? 0.32 : 0.62), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .padding(0.8)
                        }
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                        )
                        .shadow(color: accent.opacity(0.18), radius: 9, y: 2)
                        .matchedGeometryEffect(id: "floating.tab.glow.pill", in: tabPillAnimation)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var inactiveColor: Color {
        scheme == .dark ? Color(hex: "C8BCD9") : Color(hex: "625A72")
    }
}

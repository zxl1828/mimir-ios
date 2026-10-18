import SwiftUI

/// Floating command dock with an expanding active destination.
struct FloatingTabBar: View {

    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(height: 66)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.76))
        }
        .liquidGlass(.regular.tint(Color(hex: "7D52F4").opacity(0.08)), in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.86),
                    lineWidth: 1.0
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.white.opacity(0.30),
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
            color: Color(hex: "7D52F4").opacity(0.12),
            radius: 24,
            x: 0,
            y: 10
        )
        .frame(maxWidth: 360)
        .padding(.horizontal, 16)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            if selectedTab != tab {
                Haptics.selectionChanged()
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = tab
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tab.functionColor : inactiveColor)
                    .frame(width: 18)

                if isSelected {
                    Text(tab.shortTitle)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "35264A"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(tab.functionColor.opacity(0.12))
                        .liquidGlass(.regular.tint(tab.functionColor.opacity(0.18)), in: .capsule)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.62), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .padding(0.8)
                        }
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                        )
                        .shadow(color: tab.functionColor.opacity(0.18), radius: 9, y: 2)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var inactiveColor: Color { Color(hex: "81768D") }
}

private extension AppTab {
    var functionColor: Color {
        switch self {
        case .assistant: return Color(hex: "7D52F4")
        case .dashboard: return Color(hex: "3977E8")
        case .files: return Color(hex: "28A89B")
        case .code: return Color(hex: "D87B40")
        }
    }

    var shortTitle: String {
        switch self {
        case .assistant: "Assist"
        case .dashboard: "Home"
        case .files: "Files"
        case .code: "Code"
        }
    }
}

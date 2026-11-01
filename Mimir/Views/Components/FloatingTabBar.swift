import SwiftUI

/// 底部三大核心导航命令坞（Floating Glass Command Dock）。
///
/// 严格遵循 Mimir Design DNA：
/// 1. 采用原生液态玻璃修饰符 `liquidGlass` / `glassEffect` 与 `GlassContainer`；
/// 2. 严禁普通 Material 模糊与不透明纯色遮挡；
/// 3. 支持主页、文件库与 AI 生图三大导航切位；
/// 4. 刚性触控反馈，杜绝边缘异动与紫色光晕炸裂。
struct FloatingTabBar: View {

    @Binding var selectedTab: AppTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassContainer {
            HStack(spacing: 4) {
                ForEach(AppTab.bottomNavigationCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: 64)
            .background {
                Capsule(style: .continuous)
                    .fill((scheme == .dark ? Color(hex: "120D1D") : Color.white).opacity(scheme == .dark ? 0.76 : 0.84))
            }
            .liquidGlass(.regular.tint(Color(hex: "7D52F4").opacity(0.09)), in: .capsule)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.88),
                                Color(hex: "7D52F4").opacity(0.35),
                                Color.white.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
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
                                Color.white.opacity(0.24),
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
                color: Color(hex: "7D52F4").opacity(0.14),
                radius: 20,
                x: 0,
                y: 8
            )
            .frame(maxWidth: 350)
            .padding(.horizontal, 16)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            if selectedTab != tab {
                Haptics.selectionChanged()
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? tab.functionColor : inactiveColor)
                    .frame(width: 20)

                if isSelected {
                    Text(tab.shortTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(scheme == .dark ? Color(hex: "F8F6FD") : Color(hex: "120D1D"))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(tab.functionColor.opacity(0.14))
                        .liquidGlass(.regular.tint(tab.functionColor.opacity(0.20)), in: .capsule)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.9)
                        }
                        .shadow(color: tab.functionColor.opacity(0.18), radius: 8, y: 2)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var inactiveColor: Color {
        scheme == .dark ? Color(hex: "D7CBE8").opacity(0.72) : Color(hex: "81768D")
    }
}

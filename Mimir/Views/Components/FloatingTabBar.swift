import SwiftUI

/// 底部三大核心导航命令坞。
///
/// 设计约束：
/// 1. 整条坞与选中项都用 iOS 26 的原生液态玻璃（`nativeGlass`），不再自己叠渐变描边；
/// 2. 圆角跟着全局 token 走（`AppUI.cardRadius`），比过去 13 的方角顺眼得多；
/// 3. 选中态颜色取用户设置的强调色，不再写死紫色；
/// 4. 点按只做原生缩放反馈，没有光晕炸裂。
struct FloatingTabBar: View {

    @Binding var selectedTab: AppTab
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    private let barRadius: CGFloat = 22

    var body: some View {
        GlassContainer {
            HStack(spacing: 4) {
                ForEach(AppTab.bottomNavigationCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(height: 62)
            .nativeGlass(.rect(cornerRadius: barRadius), interactive: false)
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
                    .font(.system(size: 16.5, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20)

                if isSelected {
                    Text(tab.shortTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .foregroundStyle(isSelected ? accent : inactiveColor)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.20 : 0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(accent.opacity(scheme == .dark ? 0.34 : 0.20), lineWidth: 0.5)
                        }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var inactiveColor: Color {
        scheme == .dark ? Color.white.opacity(0.56) : Color(hex: "64748B")
    }
}

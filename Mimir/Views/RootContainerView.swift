import SwiftUI
import UIKit

/// 全局多工作区根容器（RootContainerView）。
///
/// 核心导航架构：
/// 1. 顶部：智能助手与代码工坊双选切换栏（`AssistantCodeSwitcher`），使用原生液态玻璃；
/// 2. 底部：三大核心工作区导航栏（`FloatingTabBar`：主页、文件库、AI生图），使用原生液态玻璃；
/// 3. 四大工作区常驻内存，保持状态不被重置；
/// 4. 键盘弹起精准避让与 TabBar 平滑下沉（offset: 100, opacity: 0）。
public struct RootContainerView: View {

    @Environment(AppSettings.self) private var settings

    @State private var coordinator = TabNavigationCoordinator.shared
    @State private var isKeyboardVisible = false

    public init() {}

    public var body: some View {
        @Bindable var coord = coordinator

        ZStack(alignment: .bottom) {
            AppBackgroundView(background: settings.background)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .zIndex(-1)

            // 常驻工作区栈（保持各页面独立滚动与交互状态）
            ZStack {
                // 主页 -> 智能助手
                AssistantMainView()
                    .opacity(isAssistantActive ? 1 : 0)
                    .allowsHitTesting(isAssistantActive)
                    .zIndex(isAssistantActive ? 2 : 1)

                // 主页 -> 代码工坊
                CodeWorkspaceCLIView()
                    .opacity(isCodeActive ? 1 : 0)
                    .allowsHitTesting(isCodeActive)
                    .zIndex(isCodeActive ? 2 : 1)

                // 文件库
                FilesAssetsView()
                    .opacity(coordinator.selectedTab == .files ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .files)
                    .zIndex(coordinator.selectedTab == .files ? 2 : 1)

                // AI 生图工坊
                ImageGenerationView()
                    .opacity(coordinator.selectedTab == .imageGen ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .imageGen)
                    .zIndex(coordinator.selectedTab == .imageGen ? 2 : 1)
            }
            .animation(.easeInOut(duration: 0.18), value: coordinator.selectedTab)
            .animation(.easeInOut(duration: 0.18), value: coordinator.topMode)

            // 悬浮式原生液态玻璃底栏（Floating Glass TabBar）
            FloatingTabBar(selectedTab: $coord.selectedTab)
                .padding(.bottom, 12)
                .offset(y: (isKeyboardVisible || !coordinator.isTabBarVisible) ? 100 : 0)
                .opacity((isKeyboardVisible || !coordinator.isTabBarVisible) ? 0 : 1)
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.82),
                    value: isKeyboardVisible || !coordinator.isTabBarVisible
                )
                .allowsHitTesting(!isKeyboardVisible && coordinator.isTabBarVisible)
                .zIndex(10)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topNavigationHeader
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 60)
                .onEnded { value in
                    guard value.startLocation.x < 28 || value.startLocation.x > UIScreen.main.bounds.width - 28,
                          abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    if coordinator.selectedTab == .home {
                        if coordinator.topMode == .assistant && value.translation.width < 0 {
                            coordinator.switchToMode(.code)
                        } else if coordinator.topMode == .code && value.translation.width > 0 {
                            coordinator.switchToMode(.assistant)
                        }
                    }
                }
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                isKeyboardVisible = false
            }
        }
    }

    private var isAssistantActive: Bool {
        coordinator.selectedTab == .home && coordinator.topMode == .assistant
    }

    private var isCodeActive: Bool {
        coordinator.selectedTab == .home && coordinator.topMode == .code
    }

    private var topNavigationHeader: some View {
        GlassContainer {
            AssistantCodeSwitcher(selectedMode: coordinator.topMode) { mode in
                coordinator.switchToMode(mode)
            }
            .padding(.top, 5)
            .padding(.bottom, 5)
        }
    }
}

// MARK: - 顶部智能助手与代码工坊双选切换栏 (Native Liquid Glass)

private struct AssistantCodeSwitcher: View {
    let selectedMode: AssistantCodeMode
    let onSelect: (AssistantCodeMode) -> Void
    @Environment(\.colorScheme) private var scheme

    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")

    var body: some View {
        HStack(spacing: 4) {
            segment(.assistant)
            segment(.code)
        }
        .padding(4)
        .background(
            Capsule()
                .fill((scheme == .dark ? deepPlumBase : Color.white).opacity(scheme == .dark ? 0.72 : 0.80))
        )
        .liquidGlass(.regular.tint(irisViolet.opacity(0.12)), in: .capsule)
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            irisViolet.opacity(0.35),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: irisViolet.opacity(0.12), radius: 14, y: 4)
        .frame(maxWidth: 310)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ mode: AssistantCodeMode) -> some View {
        let active = selectedMode == mode
        return Button {
            Haptics.selectionChanged()
            onSelect(mode)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: active ? .bold : .medium))
                Text(mode.title)
                    .font(.system(size: 12, weight: active ? .bold : .medium))
            }
            .foregroundStyle(active ? Color.white : (scheme == .dark ? Color(hex: "E8DFF5") : Color(hex: "493A5E")))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background {
                if active {
                    Capsule()
                        .fill(irisViolet.opacity(0.94))
                        .liquidGlass(.regular.tint(irisViolet.opacity(0.28)), in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8))
                        .shadow(color: irisViolet.opacity(0.32), radius: 8, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

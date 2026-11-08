import SwiftUI
import UIKit

/// 全局根容器（RootContainerView）。
///
/// 导航架构（母子页面）：
/// 1. 主页 = `ConsoleHomeView`，它自带 `NavigationStack`，聊天页与代码台都以 Push 方式进入；
/// 2. Push 进子页面时 `TabNavigationCoordinator.isTabBarVisible` 被置为 false，底部 TabBar 自动下沉隐藏；
/// 3. 文件库与 AI 生图仍是根级 Tab，保持常驻内存、状态不重置；
/// 4. 页面间不再有顶部分段切换条——层级关系只靠 Push/Pop 表达。
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

            ZStack {
                // 主页控制台（内含 Push 出去的聊天页 / 代码台）
                ConsoleHomeView()
                    .opacity(coordinator.selectedTab == .home ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .home)
                    .zIndex(coordinator.selectedTab == .home ? 2 : 1)

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

            // 悬浮式底部导航栏
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
        .onChange(of: coordinator.selectedTab) { _, _ in
            // 切换根级 Tab 时确保导航栏可见（子页面已自行隐藏）
            if coordinator.selectedTab != .home {
                coordinator.isTabBarVisible = true
            }
        }
    }
}

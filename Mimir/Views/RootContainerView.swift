import SwiftUI

/// 全局多工作区根容器（RootContainerView）。
///
/// 串联四大核心工作区，并通过悬浮毛玻璃底栏（Floating Tab Bar）切换：
/// - Tab 1: 智能助手 (AI Assistant) —— 核心对话、多轮推理与星尘阶梯滑块（AssistantMainView）
/// - Tab 2: 工作台仪表盘 (Dashboard) —— 综合监控、快速技能与任务总览（DashboardView）
/// - Tab 3: 知识资产库 (Files & Assets) —— 手机本地工作区挂载、RAG 资料库与多模态资产（FilesAssetsView）
/// - Tab 4: 代码工坊 (Code Workspace) —— 沉浸式代码审查、Web 实时预览与 MCP 编译控制台（CodeWorkspaceCLIView）
///
/// 键盘弹起精准避让与 TabBar 智能隐藏：
/// 1. 移除根容器盲目添加的 `.ignoresSafeArea(.keyboard)`；
/// 2. 激活输入时 TabBar 沿 Y 轴平滑下沉 100pt 并淡出（offset: 100, opacity: 0）；
/// 3. 四大工作区常驻内存，保持状态不被重置。
public struct RootContainerView: View {

    @State private var coordinator = TabNavigationCoordinator.shared
    @State private var isKeyboardVisible = false

    public init() {}

    public var body: some View {
        @Bindable var coord = coordinator

        ZStack(alignment: .bottom) {
            // 4 大页面常驻栈（保持各页面独立滚动与交互状态）
            ZStack {
                AssistantMainView()
                    .opacity(coordinator.selectedTab == .assistant ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .assistant)
                    .zIndex(coordinator.selectedTab == .assistant ? 2 : 1)

                DashboardView()
                    .opacity(coordinator.selectedTab == .dashboard ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .dashboard)
                    .zIndex(coordinator.selectedTab == .dashboard ? 2 : 1)

                FilesAssetsView()
                    .opacity(coordinator.selectedTab == .files ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .files)
                    .zIndex(coordinator.selectedTab == .files ? 2 : 1)

                CodeWorkspaceCLIView()
                    .opacity(coordinator.selectedTab == .code ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .code)
                    .zIndex(coordinator.selectedTab == .code ? 2 : 1)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: coordinator.selectedTab)

            // 悬浮式毛玻璃底栏（Floating Glass TabBar）
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
    }
}

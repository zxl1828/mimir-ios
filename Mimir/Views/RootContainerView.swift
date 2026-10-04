import SwiftUI

/// 全局多工作区根容器（RootContainerView）。
///
/// 串联四大核心工作区，并通过悬浮毛玻璃底栏（Floating Tab Bar）切换：
/// - Tab 1: 智能助手 (AI Assistant) —— 核心对话、多轮推理与星尘阶梯滑块
/// - Tab 2: 工作台仪表盘 (Dashboard) —— 综合监控、快速技能与任务总览
/// - Tab 3: 知识资产库 (Files & Assets) —— 手机本地工作区挂载、RAG 资料库与多模态资产
/// - Tab 4: 代码工坊 (Code Workspace) —— 沉浸式代码审查、Web 实时预览与 MCP 编译控制台
///
/// 所有页面常驻内存以保持状态不销毁（State Preservation），支持无缝平滑转场与输入时底栏避让。
struct RootContainerView: View {

    @State private var coordinator = TabNavigationCoordinator.shared
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var coord = coordinator

        ZStack(alignment: .bottom) {
            // 4 大页面常驻栈（保持各页面独立滚动与交互状态）
            ZStack {
                MainChatView()
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

                CodeWorkspaceView()
                    .opacity(coordinator.selectedTab == .code ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .code)
                    .zIndex(coordinator.selectedTab == .code ? 2 : 1)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: coordinator.selectedTab)

            // 悬浮式毛玻璃底栏（Floating Glass TabBar）
            if !isKeyboardVisible && coordinator.isTabBarVisible {
                FloatingTabBar(selectedTab: $coord.selectedTab)
                    .padding(.bottom, 12)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .offset(y: 80).combined(with: .opacity)
                        )
                    )
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isKeyboardVisible = false
            }
        }
    }
}

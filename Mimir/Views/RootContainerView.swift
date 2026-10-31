import SwiftUI
import UIKit

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
            .animation(.easeInOut(duration: 0.18), value: coordinator.selectedTab)

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
        .safeAreaInset(edge: .top, spacing: 0) {
            AssistantCodeSwitcher(selectedTab: coordinator.assistantCodeTab) { tab in
                coordinator.switchToTab(tab)
            }
                .padding(.top, 5)
                .padding(.bottom, 5)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 60)
                .onEnded { value in
                    guard value.startLocation.x < 28 || value.startLocation.x > UIScreen.main.bounds.width - 28,
                          abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    switch coordinator.selectedTab {
                    case .assistant where value.translation.width < 0:
                        coordinator.switchToTab(.code)
                    case .code where value.translation.width > 0:
                        coordinator.switchToTab(.assistant)
                    case .dashboard, .files:
                        coordinator.switchToTab(value.translation.width > 0 ? .assistant : coordinator.assistantCodeTab)
                    default:
                        break
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
}

private struct AssistantCodeSwitcher: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            segment(.assistant, title: "智能助手", icon: "sparkles")
            segment(.code, title: "代码工坊", icon: "chevron.left.forwardslash.chevron.right")
        }
        .padding(4)
        .background(Color(hex: "120D1D").opacity(scheme == .dark ? 0.72 : 0.16), in: Capsule())
        .liquidGlass(.regular.tint(Color(hex: "7D52F4").opacity(0.13)), in: .capsule)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.62), lineWidth: 0.8))
        .frame(maxWidth: 320)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ tab: AppTab, title: String, icon: String) -> some View {
        let active = selectedTab == tab
        return Button {
            Haptics.selectionChanged()
            onSelect(tab)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.white : (scheme == .dark ? Color(hex: "E8DFF5") : Color(hex: "493A5E")))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    if active {
                        Capsule().fill(Color(hex: "7D52F4").opacity(0.92))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.68), lineWidth: 0.8))
                            .shadow(color: Color(hex: "7D52F4").opacity(0.24), radius: 8, y: 2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

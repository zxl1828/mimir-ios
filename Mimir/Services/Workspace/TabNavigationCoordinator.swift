import SwiftUI
import Observation

/// 全局底部 Tab 选项定义。
enum AppTab: Int, CaseIterable, Identifiable, Sendable {
    case assistant = 0   // 智能助手
    case dashboard = 1   // 工作台仪表盘
    case files = 2       // 知识资产库
    case code = 3        // 代码工坊

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .assistant: return "AI Assistant"
        case .dashboard: return "Dashboard"
        case .files: return "Files"
        case .code: return "Code"
        }
    }

    var icon: String {
        switch self {
        case .assistant: return "sparkles"
        case .dashboard: return "square.grid.2x2"
        case .files: return "folder"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// 全局导航与跨工作区联动协调器。
@MainActor
@Observable
final class TabNavigationCoordinator {

    static let shared = TabNavigationCoordinator()

    var selectedTab: AppTab = .assistant
    var isTabBarVisible: Bool = true

    /// 跨工作区向助手注入的 Prompt 与上下文附件
    var pendingPromptToChat: String?
    var pendingAttachedFile: WorkspaceFileItem?
    var pendingOpenConversationID: UUID?
    var shouldStartNewChat: Bool = false

    private init() {}

    func switchToTab(_ tab: AppTab) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            selectedTab = tab
        }
    }

    func startNewChat() {
        shouldStartNewChat = true
        switchToTab(.assistant)
    }

    func openConversation(id: UUID) {
        pendingOpenConversationID = id
        switchToTab(.assistant)
    }

    func attachFileToChat(_ file: WorkspaceFileItem) {
        pendingAttachedFile = file
        pendingPromptToChat = "请分析以下文件【\(file.name)】的内容与逻辑结构："
        switchToTab(.assistant)
    }

    func askAIToRefactorCode(prompt: String, file: WorkspaceFileItem?) {
        pendingAttachedFile = file
        pendingPromptToChat = prompt
        switchToTab(.assistant)
    }
}

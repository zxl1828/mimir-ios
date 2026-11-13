import SwiftUI
import Observation

/// 顶部“智能助手”与“代码工坊”双选模式。
enum AssistantCodeMode: String, CaseIterable, Identifiable, Sendable {
    case assistant = "智能助手"
    case code = "代码工坊"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .assistant: return "sparkles"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// 全局底部三大核心导航 Tab。
enum AppTab: Int, CaseIterable, Identifiable, Sendable {
    case home = 0       // 主页 (承载 智能助手 / 代码工坊)
    case files = 1      // 文件库 (知识资产库与本地文件夹)
    case imageGen = 2   // AI生图 (独立创意生成面板)

    // 历史兼容枚举值（防止其他模块遗留代码引用报错）
    case assistant = 10
    case code = 11
    case dashboard = 12

    /// 底部导航栏渲染的三大金刚入口
    static var bottomNavigationCases: [AppTab] { [.home, .files, .imageGen] }

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home, .assistant, .dashboard: return "主页"
        case .files: return "文件库"
        case .imageGen: return "AI生图"
        case .code: return "代码工坊"
        }
    }

    var shortTitle: String {
        switch self {
        case .home, .assistant, .dashboard: return "主页"
        case .files: return "文件库"
        case .imageGen: return "AI生图"
        case .code: return "代码"
        }
    }

    var icon: String {
        switch self {
        case .home, .assistant: return "house"
        case .dashboard: return "square.grid.2x2"
        case .files: return "folder.fill"
        case .imageGen: return "photo.on.rectangle.angled"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var functionColor: Color {
        switch self {
        case .home, .assistant: return AppUI.consoleSignal // Iris Violet
        case .dashboard: return Color(hex: "3977E8")
        case .files: return Color(hex: "28A89B") // Teal
        case .imageGen: return Color(hex: "E056FD") // Iridescent Magenta
        case .code: return Color(hex: "D87B40") // Amber
        }
    }
}

/// 全局导航与跨工作区联动协调器。
@MainActor
@Observable
final class TabNavigationCoordinator {

    static let shared = TabNavigationCoordinator()

    /// 底部选中的 Tab（主页 / 文件库 / AI生图）
    var selectedTab: AppTab = .home

    /// 顶部双选切换栏模式（智能助手 vs 代码工坊）
    var topMode: AssistantCodeMode = .assistant

    /// 兼容已有代码
    var assistantCodeTab: AppTab {
        get { topMode == .code ? .code : .assistant }
        set { topMode = (newValue == .code ? .code : .assistant) }
    }

    var isTabBarVisible: Bool = true

    /// 跨工作区向助手注入的 Prompt 与上下文附件
    var pendingPromptToChat: String?
    var pendingImageGenerationPromptToChat: String?
    var pendingAttachedFile: WorkspaceFileItem?
    var pendingOpenConversationID: UUID?
    var shouldStartNewChat: Bool = false

    private init() {}

    func switchToTab(_ tab: AppTab) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            switch tab {
            case .home:
                selectedTab = .home
            case .assistant:
                topMode = .assistant
                selectedTab = .home
            case .code:
                topMode = .code
                selectedTab = .home
            case .files:
                selectedTab = .files
            case .imageGen:
                selectedTab = .imageGen
            case .dashboard:
                selectedTab = .home
            }
        }
    }

    func setTab(_ tab: AppTab) {
        switchToTab(tab)
    }

    func switchToMode(_ mode: AssistantCodeMode) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            topMode = mode
            selectedTab = .home
        }
    }

    func startNewChat() {
        shouldStartNewChat = true
        topMode = .assistant
        switchToTab(.home)
    }

    func navigateToAssistant(withPrompt prompt: String) {
        pendingPromptToChat = prompt
        topMode = .assistant
        switchToTab(.home)
    }

    func navigateToAssistantForImageGeneration(withPrompt prompt: String = "描述你想生成的图片：") {
        pendingImageGenerationPromptToChat = prompt
        switchToTab(.imageGen)
    }

    func openConversation(id: UUID) {
        pendingOpenConversationID = id
        topMode = .assistant
        switchToTab(.home)
    }

    func attachFileToChat(_ file: WorkspaceFileItem) {
        pendingAttachedFile = file
        pendingPromptToChat = "请分析以下文件【\(file.name)】的内容与逻辑结构："
        topMode = .assistant
        switchToTab(.home)
    }

    func askAIToRefactorCode(prompt: String, file: WorkspaceFileItem?) {
        pendingAttachedFile = file
        pendingPromptToChat = prompt
        topMode = .assistant
        switchToTab(.home)
    }
}

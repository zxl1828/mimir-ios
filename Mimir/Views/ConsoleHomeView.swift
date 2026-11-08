import SwiftUI
import SwiftData
import UIKit

/// 550C 控制台首页（`ConsoleHomeView`）。
///
/// 结构自上而下：
/// 1. 品牌行：550C 标识 + 版本标签，右侧用户头像与设置；
/// 2. 设备胶囊：本机名 + 工作区连接状态；
/// 3. 主视觉：大号粗体「探索未至之境」+ 版本副标；
/// 4. 工作区卡片（16 连续圆角）→ 点按进入代码工作台；
/// 5. 「+ 新建会话」通栏按钮（14 连续圆角）；
/// 6. 搜索框 + 最近会话列表 → 点按 Push 进独立聊天页。
///
/// 母子页面：首页只做"控制台"，所有会话都在 Push 出去的子页面里，
/// 子页面出现时隐藏底部 TabBar（通过 `TabNavigationCoordinator.isTabBarVisible`）。
struct ConsoleHomeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    @State private var workspace = WorkspaceManager.shared
    @State private var coordinator = TabNavigationCoordinator.shared

    @State private var path = NavigationPath()
    @State private var list: ConversationListViewModel?
    @State private var showSettings = false
    @State private var didBootstrap = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: ConsoleRoute.self) { route in
                    switch route {
                    case .chat(let id):
                        AssistantMainView(initialConversationID: id, showsBackButton: true)
                    case .code:
                        CodeWorkspaceCLIView(showsBackButton: true)
                    }
                }
        }
        .task { bootstrap() }
        .onChange(of: path.count) { _, depth in
            // 进入子页面：隐藏底部 TabBar，回到首页再恢复。
            withAnimation(.easeInOut(duration: 0.2)) {
                coordinator.isTabBarVisible = (depth == 0)
            }
        }
        .onChange(of: coordinator.shouldStartNewChat) { _, shouldStart in
            guard shouldStart else { return }
            coordinator.shouldStartNewChat = false
            path.append(ConsoleRoute.chat(nil))
        }
        .onChange(of: coordinator.pendingOpenConversationID) { _, convoID in
            guard let convoID else { return }
            coordinator.pendingOpenConversationID = nil
            path.append(ConsoleRoute.chat(convoID))
        }
    }

    // MARK: - 内容

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                brandRow
                deviceCapsule
                heroBlock
                workspaceCard
                newSessionButton
                sessionSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            if let list {
                SettingsView(chat: ScratchChatFactory.make(context: modelContext, settings: settings), list: list)
            }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppUI.consoleSignal)

                Text("MIMIR")
                    .font(AppUI.mono(17, weight: .black))
                    .tracking(2.2)
                    .foregroundStyle(AppUI.label)

                Text("550C")
                    .font(AppUI.mono(9.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(AppUI.consoleSignal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(AppUI.consoleSignal.opacity(0.5), lineWidth: 0.5)
                    )
            }

            Spacer(minLength: 8)

            headerCircleButton(icon: "person.fill") { showSettings = true }
            headerCircleButton(icon: "gearshape.fill") { showSettings = true }
        }
    }

    private func headerCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppUI.label2)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppUI.consolePanel(scheme: scheme)))
                .overlay(Circle().strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 0.5))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
    }

    private var deviceCapsule: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppUI.label2)

            Text(UIDevice.current.name)
                .font(AppUI.mono(11, weight: .medium))
                .foregroundStyle(AppUI.label2)
                .lineLimit(1)

            Circle()
                .fill(workspaceConnected ? Color(red: 0.22, green: 0.78, blue: 0.46) : AppUI.label3)
                .frame(width: 5.5, height: 5.5)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppUI.label3)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(AppUI.consolePanel(scheme: scheme).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 0.5))
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("探索未至之境")
                .font(.system(size: 34, weight: .black))
                .tracking(-0.8)
                .foregroundStyle(AppUI.label)

            HStack(spacing: 8) {
                Text("Mimir 私人 AI 控制台")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppUI.label2)

                Text("v2.4")
                    .font(AppUI.mono(10, weight: .semibold))
                    .foregroundStyle(AppUI.consoleSignalDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(AppUI.consoleSignal.opacity(0.10))
                    )
            }
        }
        .padding(.top, 6)
    }

    private var workspaceCard: some View {
        Button {
            Haptics.impact(.light)
            path.append(ConsoleRoute.code)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppUI.consoleSignal)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppUI.consoleSignal.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(workspaceName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AppUI.label)
                        .lineLimit(1)

                    Text(workspacePath)
                        .font(AppUI.mono(10))
                        .foregroundStyle(AppUI.label3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                Circle()
                    .fill(workspaceConnected ? Color(red: 0.22, green: 0.78, blue: 0.46) : AppUI.label3)
                    .frame(width: 6, height: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppUI.label3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppUI.consolePanel(scheme: scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var newSessionButton: some View {
        Button {
            Haptics.impact(.medium)
            path.append(ConsoleRoute.chat(nil))
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("新建会话")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(scheme == .dark ? Color(red: 0.02, green: 0.06, blue: 0.12) : .white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(scheme == .dark ? AppUI.consoleSignal : AppUI.consoleSignal)
            )
        }
        .buttonStyle(StaticButtonFeedbackStyle())
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("最近会话")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AppUI.label)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.78, blue: 0.46))
                        .frame(width: 5, height: 5)
                    Text("已连接")
                        .font(AppUI.mono(10, weight: .medium))
                        .foregroundStyle(Color(red: 0.30, green: 0.72, blue: 0.48))
                }
            }

            searchField

            VStack(spacing: 2) {
                let conversations = list?.filteredConversations ?? []
                if conversations.isEmpty {
                    Text("还没有会话，点上面的「新建会话」开始。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppUI.label3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                } else {
                    ForEach(conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppUI.label3)

            TextField(
                "搜索会话内容",
                text: Binding(
                    get: { list?.searchText ?? "" },
                    set: { list?.searchText = $0 }
                )
            )
            .font(.system(size: 13))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AppUI.consolePanel(scheme: scheme).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 0.5)
        )
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            Haptics.selectionChanged()
            path.append(ConsoleRoute.chat(conversation.id))
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(conversation.isPinned ? AppUI.consoleSignal : AppUI.label3.opacity(0.6))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AppUI.label)
                        .lineLimit(1)

                    Text(conversation.messages.isEmpty ? "空会话" : "\(conversation.messages.count) 条消息")
                        .font(AppUI.mono(9.5))
                        .foregroundStyle(AppUI.label3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(AppUI.mono(9.5))
                    .foregroundStyle(AppUI.label3)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppUI.label3.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    private var workspaceConnected: Bool {
        if case .mounted = workspace.mountState { return true }
        return false
    }

    private var workspaceName: String {
        if case .mounted(let name, _, _, _) = workspace.mountState { return name }
        return workspace.activeWorkspaceURL?.lastPathComponent ?? "Mimir Workspace"
    }

    private var workspacePath: String {
        if case .mounted(_, let path, _, _) = workspace.mountState { return path }
        return workspace.activeWorkspaceURL?.path ?? "Documents/Mimir Workspace"
    }

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        let viewModel = ConversationListViewModel(modelContext: modelContext, settings: settings)
        viewModel.refresh()
        list = viewModel
    }
}

/// 首页子页面路由。
enum ConsoleRoute: Hashable {
    case chat(UUID?)
    case code
}

/// 首页仅为了打开设置页而需要一个 `ChatViewModel` 实例，这里集中构造，避免散落。
@MainActor
private enum ScratchChatFactory {
    static func make(context: ModelContext, settings: AppSettings) -> ChatViewModel {
        ChatViewModel(modelContext: context, settings: settings)
    }
}

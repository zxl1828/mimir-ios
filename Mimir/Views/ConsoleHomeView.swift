/// 首页：私人助手的控制台。
///
/// 结构自上而下：
/// 1. 品牌行：MIMIR 标识 + 唯一的设置入口；
/// 2. 问候区：按时段问候 + 一句工作区概览（不再放版本徽标与设备胶囊）；
/// 3. 工作区卡片（16 连续圆角）→ 点按进入代码工作台；
/// 4. 「+ 新建会话」通栏按钮（14 连续圆角）；
/// 5. 搜索框 + 最近会话列表（左滑删除，空会话不落库）。

import SwiftUI
import SwiftData
import UIKit

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
    @State private var renamingConversation: Conversation?
    @State private var renameDraft = ""

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: ConsoleRoute.self) { route in
                    switch route {
                    case .chat(let id):
                        AssistantMainView(
                            initialConversationID: id,
                            startsNewConversation: id == nil,
                            showsBackButton: true
                        )
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
            // 从聊天页返回时刷新列表，刚建的会话与标题更新立刻可见。
            if depth == 0 {
                list?.refresh()
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
        .alert(
            "重命名会话",
            isPresented: Binding(
                get: { renamingConversation != nil },
                set: { if !$0 { renamingConversation = nil } }
            )
        ) {
            TextField("会话名称", text: $renameDraft)
            Button("取消", role: .cancel) { renamingConversation = nil }
            Button("保存") {
                if let target = renamingConversation {
                    list?.rename(target, to: renameDraft)
                }
                renamingConversation = nil
            }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)

            Text("MIMIR")
                .font(AppUI.mono(17, weight: .black))
                .tracking(2.2)
                .foregroundStyle(AppUI.label)

            Spacer(minLength: 8)

            // 全局唯一的设置入口：顶部不再挂版本号、设备名等调试信息。
            headerCircleButton(icon: "gearshape.fill") { showSettings = true }
        }
    }

    private func headerCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppUI.label2)
                .frame(width: 38, height: 38)
                .nativeGlass(.circle)
                .contentShape(Circle())
        }
        .buttonStyle(StaticButtonFeedbackStyle())
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 27, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppUI.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(workspaceSummary)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppUI.label2)
                .lineLimit(1)
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<11: prefix = "早上好"
        case 11..<14: prefix = "中午好"
        case 14..<18: prefix = "下午好"
        case 18..<23: prefix = "晚上好"
        default: prefix = "夜深了"
        }
        let name = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? prefix : "\(prefix)，\(name)"
    }

    private var workspaceSummary: String {
        let count = workspace.allFiles.count
        if count == 0 { return "随时为你处理日程、文档与代码任务" }
        return "工作区 \(count) 个文件 · 随时可以开始"
    }

    private var workspaceCard: some View {
        Button {
            Haptics.impact(.light)
            path.append(ConsoleRoute.code)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(workspaceName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AppUI.label)
                        .lineLimit(1)

                    Text(workspaceConnected ? "本地安全沙盒 · 点击管理文件" : "未挂载 · 点击选择项目文件夹")
                        .font(.system(size: 11))
                        .foregroundStyle(AppUI.label3)
                        .lineLimit(1)
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
            .nativeGlassRect(cornerRadius: 16)
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
            .foregroundStyle(AppUI.label)
            .frame(maxWidth: .infinity, minHeight: 48)
            .nativeGlassRect(cornerRadius: 14, tint: accent.opacity(0.55))
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
                        SwipeToDeleteRow(onDelete: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                list?.delete(conversation)
                            }
                        }) {
                            conversationRow(conversation)
                        }
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
        .padding(.vertical, 11)
        .nativeGlassRect(cornerRadius: 14, interactive: false)
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            Haptics.selectionChanged()
            path.append(ConsoleRoute.chat(conversation.id))
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(conversation.isPinned ? accent : AppUI.label3.opacity(0.6))
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
        .contextMenu {
            Button {
                Haptics.impact(.light)
                list?.togglePin(conversation)
            } label: {
                Label(conversation.isPinned ? "取消置顶" : "置顶会话",
                      systemImage: conversation.isPinned ? "pin.slash" : "pin")
            }

            Button {
                Haptics.impact(.light)
                renamingConversation = conversation
                renameDraft = conversation.title
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Button(role: .destructive) {
                Haptics.impact(.medium)
                withAnimation(.easeInOut(duration: 0.2)) {
                    list?.delete(conversation)
                }
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
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

/// 左滑删除容器：SwiftUI 的 `.swipeActions` 只在 `List` 里生效，
/// 首页是自定义卡片堆叠，所以这里自己实现一份等效手势——
/// 横向拖动超过阈值时露出右侧删除键，点击别处自动收回。
private struct SwipeToDeleteRow<Content: View>: View {

    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let actionWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                Haptics.impact(.medium)
                close()
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionWidth, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.90, green: 0.32, blue: 0.32))
                    )
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)
            .allowsHitTesting(isOpen)
            .padding(.trailing, 4)

            content
                .background(Color.clear)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base: CGFloat = isOpen ? -actionWidth : 0
                            offset = min(0, max(-actionWidth, base + value.translation.width))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                close()
                                return
                            }
                            let base: CGFloat = isOpen ? -actionWidth : 0
                            let projected = base + value.translation.width
                            if projected < -actionWidth / 2 {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    offset = -actionWidth
                                    isOpen = true
                                }
                            } else {
                                close()
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            offset = 0
            isOpen = false
        }
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

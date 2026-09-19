import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// 主对话界面。只呈现当前对话，导航与辅助功能全部收进左侧抽屉。
struct MainChatView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var chat: ChatViewModel?
    @State private var list: ConversationListViewModel?
    @State private var agents: [AgentDockItem] = []
    @State private var skills: [Skill] = []
    @State private var mcpConfigs: [MCPServerConfig] = []

    @State private var sidebarOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSettings = false
    @State private var showVoiceMode = false
    @State private var showMemoryBrowser = false
    @State private var showDataFlow = false
    @State private var showAgentManager = false
    @State private var showMCPServers = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingMessage: ChatMessage?
    @State private var editingText = ""
    @State private var branchTarget: ChatMessage?
    @State private var showGlobalSearch = false
    @State private var exportTarget: Conversation?
    @State private var pendingScrollTarget: UUID?
    @State private var highlightedMessageID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showAttachmentOptions = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var toast: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(proxy.size.width * 0.8, 320)

            ZStack(alignment: .leading) {
                mainColumn
                    .offset(x: sidebarOpen ? 20 + max(dragOffset, 0) : max(dragOffset, 0))
                    .animation(AppAnimation.sidebar, value: sidebarOpen)

                if sidebarOpen || dragOffset > 0 {
                    Color.black
                        .opacity(0.3 * dimProgress(sidebarWidth: sidebarWidth))
                        .ignoresSafeArea()
                        .animation(AppAnimation.sidebar, value: sidebarOpen)
                        .onTapGesture { closeSidebar() }
                        .zIndex(1)
                }

                if sidebarOpen || dragOffset > 0 {
                    sidebar(width: sidebarWidth)
                        .frame(width: sidebarWidth)
                        .ignoresSafeArea(edges: [.top, .bottom, .leading])
                        // 展开时停在屏幕内（offset 0），关闭时才推到左边外面。
                        // 之前写成 -(sidebarWidth - dragOffset)，抽屉一打开就被推出屏幕，看起来全空白。
                        .offset(x: sidebarOpen ? max(dragOffset, 0) : -(sidebarWidth - max(dragOffset, 0)))
                        .animation(AppAnimation.sidebar, value: sidebarOpen)
                        .zIndex(2)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(edgeDragGesture(sidebarWidth: sidebarWidth))
        }
        .background(AppColor.canvas)
        .task { await bootstrap() }
        .onChange(of: photoItem) { _, newValue in loadPickedPhoto(newValue) }
        .sheet(isPresented: $showSettings) {
            if let chat, let list {
                SettingsView(chat: chat, list: list)
            }
        }
        .fullScreenCover(isPresented: $showVoiceMode) {
            if let chat {
                VoiceModeView(chat: chat)
            }
        }
        .sheet(isPresented: $showMemoryBrowser) {
            MemoryBrowserView()
        }
        .sheet(isPresented: $showDataFlow) {
            DataFlowPanelView()
        }
        .sheet(isPresented: $showAgentManager) {
            AgentManagerView()
        }
        .sheet(isPresented: $showMCPServers) {
            MCPServersView()
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView { conversationID, messageID in
                openSearchResult(conversationID: conversationID, messageID: messageID)
            }
        }
        .sheet(item: $exportTarget) { conversation in
            ExportConversationSheet(conversation: conversation)
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(
                onCapture: { image in
                    appendImage(image)
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showScanner) {
            DocumentScannerView(
                onFinish: { images in
                    images.forEach(appendImage)
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .alert("重命名对话", isPresented: $editingTitle) {
            TextField("对话名称", text: $titleDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { commitTitle() }
        }
        .alert("编辑消息", isPresented: Binding(
            get: { editingMessage != nil },
            set: { if !$0 { editingMessage = nil } }
        )) {
            TextField("消息内容", text: $editingText, axis: .vertical)
            Button("取消", role: .cancel) { editingMessage = nil }
            Button("重发") {
                if let message = editingMessage {
                    chat?.resend(editing: message, newText: editingText)
                }
                editingMessage = nil
            }
        }
        .alert("从这里重新生成？", isPresented: Binding(
            get: { branchTarget != nil },
            set: { if !$0 { branchTarget = nil } }
        )) {
            Button("取消", role: .cancel) { branchTarget = nil }
            Button("继续") {
                if let target = branchTarget {
                    chat?.regenerateFrom(message: target)
                }
                branchTarget = nil
            }
        } message: {
            Text(branchDeletionHint)
        }
        .overlay(alignment: .top) { toastView }
    }

    // MARK: - 主列

    private var mainColumn: some View {
        VStack(spacing: 0) {
            topBar
            messageList
            bottomBar
        }
        .background(AppColor.canvas)
    }

    /// 顶栏：整条是一枚悬浮的液态玻璃胶囊，两侧按钮是圆形玻璃块。
    private var topBar: some View {
        HStack(spacing: 8) {
            iconButton("line.3.horizontal", label: "打开侧边栏") {
                openSidebar()
            }

            Spacer(minLength: 2)

            Button {
                Haptics.impact(.light)
                titleDraft = chat?.conversation?.title ?? ""
                editingTitle = true
            } label: {
                HStack(spacing: 5) {
                    Text(chat?.conversation?.title ?? "新对话")
                        .font(AppFont.chatTitle)
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重命名当前对话")

            Spacer(minLength: 2)

            modelMenu

            iconButton("square.and.pencil", label: "新建对话") {
                newConversation()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .liquidGlass(.regular, in: .rect(cornerRadius: 26))
        .glassHairline(cornerRadius: 26)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    /// 模型切换：胶囊显示当前模型，点开是玻璃菜单。
    private var modelMenu: some View {
        Menu {
            ForEach(ModelCatalog.options(for: settings.credential, customModels: settings.customModels)) { option in
                Button {
                    selectModel(option.id)
                } label: {
                    if option.id == currentModelID {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
            Divider()
            Button {
                showSettings = true
            } label: {
                Label("自定义模型 / 参数…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.brandIndigo)
                Text(ModelCatalog.shortLabel(for: currentModelID))
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .liquidGlass(.clear, in: .capsule)
        .capsuleHairline()
        .accessibilityLabel("切换模型")
    }

    private var currentModelID: String {
        chat?.activeModelID ?? settings.credential.modelID
    }

    /// 面板贴到屏幕顶边后，内容要自己避开灵动岛 / 状态栏。
    private var sidebarTopInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        return window?.safeAreaInsets.top ?? 20
    }

    private func selectModel(_ modelID: String) {
        Haptics.selectionChanged()
        chat?.setModel(modelID)
        toast = "已切换到 \(ModelCatalog.shortLabel(for: modelID))"
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(AppFont.navIcon)
                .foregroundStyle(AppColor.primaryText)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if chat?.messages.isEmpty ?? true {
                        emptyState
                    }

                    ForEach(chat?.messages ?? []) { message in
                        MessageBubble(
                            message: message,
                            isHighlighted: highlightedMessageID == message.id,
                            onCopy: {},
                            onRegenerate: { chat?.regenerate(message: message) },
                            onRegenerateHere: { branchTarget = message },
                            onSwitchVersion: { index in
                                chat?.switchVersion(of: message, to: index)
                            },
                            onQuote: { quote(message) },
                            onEdit: {
                                editingText = message.text
                                editingMessage = message
                            },
                            onDelete: {
                                Haptics.impact(.medium)
                                chat?.delete(message: message)
                            },
                            onOpenMemory: { _ in showMemoryBrowser = true }
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: chat?.messages.count ?? 0) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: lastMessageLength) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .task(id: pendingScrollTarget) {
                guard let target = pendingScrollTarget else { return }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(AppAnimation.bubble) {
                    proxy.scrollTo(target, anchor: .center)
                }
                highlightedMessageID = target
                pendingScrollTarget = nil
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.3)) {
                    highlightedMessageID = nil
                }
            }
        }
        .overlay(alignment: .bottom) { floatingPanels }
    }

    /// 输入框上方的浮层：技能选择器优先，其次是推荐。
    @ViewBuilder
    private var floatingPanels: some View {
        if let chat {
            if !MCPClientManager.shared.activeCalls.isEmpty {
                ToolProgressView(calls: MCPClientManager.shared.activeCalls)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            } else if chat.isSkillPickerVisible {
                SkillPicker(
                    skills: chat.filteredSkills,
                    query: chat.slashQuery ?? "",
                    highlightedIndex: chat.highlightedSkillIndex,
                    onHighlight: { chat.highlightedSkillIndex = $0 },
                    onSelect: { chat.applySkill($0) },
                    onDismiss: { chat.dismissSkillPicker(removingCommand: false) }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            } else if !chat.skillSuggestions.isEmpty || !chat.replySuggestions.isEmpty {
                SuggestionChips(
                    skillSuggestions: chat.skillSuggestions,
                    replySuggestions: chat.replySuggestions,
                    confidence: chat.recommendationConfidence,
                    onPickSkill: { chat.applySkill($0) },
                    onPickReply: { reply in
                        chat.inputText = reply
                        inputFocused = true
                    },
                    onDismiss: { chat.dismissRecommendations() }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }

    private static let bottomAnchor = "chat.bottom.anchor"

    private var lastMessageLength: Int {
        (chat?.messages.last?.text.count ?? 0) + (chat?.messages.last?.thinkingText.count ?? 0)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(AppAnimation.bubble) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MimirMascot(size: 118, mood: .calm)
                .padding(.bottom, 2)
            Text("开始一段新对话")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text("输入问题，或用 / 唤起技能")
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.bottom, 40)
    }

    private var bottomBar: some View {
        VStack(spacing: 9) {
            if let quoted = chat?.quotedMessage {
                quotedBar(quoted)
            }

            HStack(spacing: 8) {
                // 智能体胶囊占满剩余宽度并自己横向滚动，思考档位固定在右侧，
                // 这样两者永远不会重叠（之前滑块 layoutPriority 抢宽度压到了智能体按钮上）。
                AgentDock(
                    agents: agents,
                    selected: Binding(
                        get: { chat?.activeAgent },
                        set: { chat?.activeAgent = $0 }
                    ),
                    onManage: { showAgentManager = true }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ThinkingModeSlider(
                    selection: Binding(
                        get: { chat?.thinkingMode ?? .thinking },
                        set: { chat?.thinkingMode = $0 }
                    )
                )
                .fixedSize()
            }

            MessageInputBar(
                text: Binding(
                    get: { chat?.inputText ?? "" },
                    set: { chat?.inputText = $0 }
                ),
                attachments: Binding(
                    get: { chat?.attachedImages ?? [] },
                    set: { chat?.attachedImages = $0 }
                ),
                focus: $inputFocused,
                isGenerating: chat?.isGenerating ?? false,
                onSend: { chat?.send() },
                onStop: { chat?.stopGenerating() },
                showAttachMenu: $showAttachmentOptions,
                onPickPhoto: { showPhotoPicker = true },
                onCamera: { showCamera = true },
                onScan: { showScanner = true },
                onVoice: { showVoiceMode = true },
                onTextChanged: { chat?.handleInputChange($0) },
                onKeyCommand: { chat?.handleKeyCommand($0) ?? false }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.separator.opacity(0.22))
                .frame(height: 0.5)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
    }

    private func quotedBar(_ message: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.brandIndigo)
            Text(String(message.text.prefix(60)))
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                Haptics.impact(.light)
                chat?.quotedMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .liquidGlassClear(cornerRadius: 14)
        .padding(.horizontal, 2)
    }

    // MARK: - 侧边栏

    private func sidebar(width: CGFloat) -> some View {
        SidebarView(
            list: list,
            agents: agents,
            skills: skills,
            currentConversationID: chat?.conversation?.id,
            topInset: sidebarTopInset,
            onSelectConversation: { conversation in
                chat?.attach(to: conversation)
                list?.markUsed(conversation)
                closeSidebar()
            },
            onNewConversation: {
                newConversation()
                closeSidebar()
            },
            onOpenSettings: {
                closeSidebar()
                showSettings = true
            },
            onOpenMemory: {
                closeSidebar()
                showMemoryBrowser = true
            },
            onOpenDataFlow: {
                closeSidebar()
                showDataFlow = true
            },
            onOpenMCP: {
                closeSidebar()
                showMCPServers = true
            },
            onSearchAll: {
                closeSidebar()
                showGlobalSearch = true
            },
            onExportConversation: { conversation in
                closeSidebar()
                exportTarget = conversation
            },
            onSelectAgent: { agent in
                chat?.activeAgent = agent
                settings.selectedAgentName = agent?.name ?? ""
                closeSidebar()
            },
            onSelectSkill: { skill in
                chat?.activeSkill = skill
                closeSidebar()
            }
        )
        .frame(width: width)
    }

    private func dimProgress(sidebarWidth: CGFloat) -> Double {
        if sidebarOpen { return 1 }
        return min(max(Double(dragOffset / max(sidebarWidth, 1)), 0), 1)
    }

    private func edgeDragGesture(sidebarWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !sidebarOpen else { return }
                let startX = value.startLocation.x
                guard startX < 24 else { return }
                dragOffset = min(max(value.translation.width, 0), sidebarWidth)
            }
            .onEnded { value in
                guard !sidebarOpen else { return }
                let shouldOpen = value.translation.width > sidebarWidth * 0.35
                withAnimation(AppAnimation.sidebar) {
                    dragOffset = 0
                }
                if shouldOpen { openSidebar() }
            }
    }

    private func openSidebar() {
        Haptics.impact(.light)
        list?.refresh()
        withAnimation(AppAnimation.sidebar) { sidebarOpen = true }
    }

    private func closeSidebar() {
        withAnimation(AppAnimation.sidebar) { sidebarOpen = false }
    }

    // MARK: - 数据

    private func bootstrap() async {
        guard chat == nil else { return }
        let chatViewModel = ChatViewModel(modelContext: modelContext, settings: settings)
        let listViewModel = ConversationListViewModel(modelContext: modelContext, settings: settings)
        listViewModel.refresh()

        agents = (try? modelContext.fetch(
            FetchDescriptor<AgentDockItem>(sortBy: [SortDescriptor(\AgentDockItem.sortIndex)])
        )) ?? []
        skills = (try? modelContext.fetch(
            FetchDescriptor<Skill>(sortBy: [SortDescriptor(\Skill.sortIndex)])
        )) ?? []

        chat = chatViewModel
        list = listViewModel
        chatViewModel.skills = skills
        mcpConfigs = (try? modelContext.fetch(FetchDescriptor<MCPServerConfig>())) ?? []
        chatViewModel.mcpConfigs = mcpConfigs
        MemoryStore.shared.warmUp(context: modelContext)

        Task {
            await MCPClientManager.shared.reconnectAll(configs: mcpConfigs)
        }

        if let last = listViewModel.conversations.first {
            chatViewModel.attach(to: last)
        } else {
            let fresh = listViewModel.createConversation()
            chatViewModel.attach(to: fresh)
        }
        listViewModel.applyRetentionPolicy()
    }

    private func newConversation() {
        guard let list, let chat else { return }
        let conversation = list.createConversation()
        chat.attach(to: conversation)
        inputFocused = true
        showToast("已新建对话")
    }

    private func commitTitle() {
        guard let conversation = chat?.conversation else { return }
        list?.rename(conversation, to: titleDraft)
    }

    /// 从全局搜索跳转：切到目标对话，并把命中的消息滚到屏幕中间高亮一下。
    private func openSearchResult(conversationID: UUID, messageID: UUID?) {
        guard let list, let chat else { return }
        guard let conversation = list.conversations.first(where: { $0.id == conversationID }) else { return }
        chat.attach(to: conversation)
        list.markUsed(conversation)
        if let messageID {
            pendingScrollTarget = messageID
        }
    }

    private func quote(_ message: ChatMessage) {
        chat?.quotedMessage = message
        inputFocused = true
    }

    /// 提示这次分支操作会折叠多少条后续消息。
    private var branchDeletionHint: String {
        guard let target = branchTarget,
              let ordered = chat?.conversation?.orderedMessages,
              let index = ordered.firstIndex(where: { $0.id == target.id }) else {
            return "这条消息会被重新生成，旧版本保留，可随时切换对比。"
        }
        let trailing = ordered.count - index - 1
        if trailing <= 0 {
            return "这条消息会保留旧版本，生成一个新的回答，之后可以左右切换对比。"
        }
        return "这条消息之后的 \(trailing) 条消息会收进分支（不会丢失），切回旧版本时可以原样恢复。"
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    chat?.attachedImages.append(data)
                }
            }
            photoItem = nil
        }
    }

    private func appendImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        chat?.attachedImages.append(data)
        Haptics.impact(.light)
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == text { toast = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(AppFont.chip)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.75)))
                .padding(.top, 54)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(AppAnimation.chip, value: toast)
        }
    }
}

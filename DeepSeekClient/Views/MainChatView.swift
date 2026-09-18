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

    @State private var sidebarOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSettings = false
    @State private var showVoiceMode = false
    @State private var showMemoryBrowser = false
    @State private var showDataFlow = false
    @State private var showAgentManager = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingMessage: ChatMessage?
    @State private var editingText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
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
                        .offset(x: -(sidebarWidth - max(dragOffset, 0)))
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

    private var topBar: some View {
        HStack(spacing: 10) {
            iconButton("line.3.horizontal", label: "打开侧边栏") {
                openSidebar()
            }

            Spacer(minLength: 4)

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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重命名当前对话")

            Spacer(minLength: 4)

            iconButton("square.and.pencil", label: "新建对话") {
                newConversation()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.separator.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(AppFont.navIcon)
                .foregroundStyle(AppColor.primaryText)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                            onCopy: {},
                            onRegenerate: { chat?.regenerateLast() },
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
        }
        .overlay(alignment: .bottom) { floatingPanels }
    }

    /// 输入框上方的浮层：技能选择器优先，其次是推荐。
    @ViewBuilder
    private var floatingPanels: some View {
        if let chat {
            if chat.isSkillPickerVisible {
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
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppColor.brandIndigo.opacity(0.7))
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
                AgentDock(
                    agents: agents,
                    selected: Binding(
                        get: { chat?.activeAgent },
                        set: { chat?.activeAgent = $0 }
                    ),
                    onManage: { showAgentManager = true }
                )

                ThinkingModeSlider(
                    selection: Binding(
                        get: { chat?.thinkingMode ?? .thinking },
                        set: { chat?.thinkingMode = $0 }
                    )
                )
                .layoutPriority(1)
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
                onAttach: { showPhotoPicker = true },
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
        MemoryStore.shared.warmUp(context: modelContext)

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

    private func quote(_ message: ChatMessage) {
        chat?.quotedMessage = message
        inputFocused = true
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

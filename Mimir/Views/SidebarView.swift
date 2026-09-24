import SwiftUI
import SwiftData
import UIKit

/// 抽屉式侧边栏：搜索、主导航、最近对话、智能体与技能，底部悬浮「聊天」。
struct SidebarView: View {

    let list: ConversationListViewModel?
    let agents: [AgentDockItem]
    let skills: [Skill]
    let currentConversationID: UUID?
    /// 面板贴到屏幕顶边后，内容需要自己让开灵动岛 / 状态栏。
    var topInset: CGFloat = 0

    var onSelectConversation: (Conversation) -> Void
    var onNewConversation: () -> Void
    var onOpenSettings: () -> Void
    var onOpenMemory: () -> Void
    var onOpenDataFlow: () -> Void
    var onOpenMCP: () -> Void
    var onSearchAll: () -> Void
    var onExportConversation: (Conversation) -> Void
    var onSelectAgent: (AgentDockItem?) -> Void
    var onSelectSkill: (Skill) -> Void
    var onPickPhoto: () -> Void = {}
    var onOpenScheduledTasks: () -> Void = {}

    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var expandedSection: SectionKey? = .history

    private enum SectionKey: String {
        case history
        case agents
        case skills
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            header
            searchField
            navList
            searchAllButton

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    historySection
                    agentsSection
                    skillsSection
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .background(AppUI.groupCanvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppUI.separator.opacity(0.5))
                .frame(width: 0.5)
                .ignoresSafeArea()
        }
        .alert("重命名对话", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("对话名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let conversation = renaming {
                    list?.rename(conversation, to: renameText)
                }
                renaming = nil
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            MimirMascot(size: 34, mood: .calm)

            VStack(alignment: .leading, spacing: 1) {
                Text("Mimir")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.label)
                Text("本地优先的私人 AI")
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
            }

            Spacer(minLength: 4)

            Button {
                Haptics.impact(.light)
                onNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppUI.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppUI.secondary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建对话")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppUI.label3)
            TextField("搜索对话", text: $searchText)
                .textFieldStyle(.plain)
                .font(AppUI.subheadline)
                .onChange(of: searchText) { _, newValue in
                    list?.searchText = newValue
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    list?.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppUI.label3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(AppUI.secondary))
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: - 主导航

    /// 固定 5 项功能入口，图标与顺序是产品规格的一部分。
    private var navList: some View {
        VStack(spacing: 2) {
            navRow(icon: "photo.on.rectangle", title: "图片") { onPickPhoto() }
            navRow(icon: "square.stack", title: "资料库") { onOpenMemory() }
            navRow(icon: "folder", title: "项目") { onOpenMCP() }
            navRow(icon: "clock", title: "定时任务") { onOpenScheduledTasks() }
            navRow(icon: "square.grid.2x2", title: "探索") { onSearchAll() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func navRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppUI.label)
                    .frame(width: 24)
                Text(title)
                    .font(AppUI.rowTitle)
                    .foregroundStyle(AppUI.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 「搜索全部对话与记忆」独立成一行：之前用 overlay 挂在搜索框底部，
    /// 既不占布局空间，又会和搜索框、对话记录标题叠在一起。
    private var searchAllButton: some View {
        Button {
            Haptics.impact(.light)
            onSearchAll()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("搜索全部对话与记忆")
                    .font(AppUI.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppUI.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppUI.fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - 对话记录

    @ViewBuilder
    private var historySection: some View {
        sectionHeader("最近", key: .history, count: list?.filteredConversations.count ?? 0)

        if expandedSection == .history {
            let pinned = list?.pinnedConversations ?? []
            let regular = list?.regularConversations ?? []

            if pinned.isEmpty && regular.isEmpty {
                emptyHint("还没有对话记录")
            }

            if !pinned.isEmpty {
                subLabel("置顶")
                ForEach(pinned) { conversation in
                    conversationRow(conversation, pinned: true)
                }
            }

            ForEach(regular) { conversation in
                conversationRow(conversation, pinned: false)
            }
        }
    }

    private func conversationRow(_ conversation: Conversation, pinned: Bool) -> some View {
        let isCurrent = conversation.id == currentConversationID
        return Button {
            Haptics.selectionChanged()
            onSelectConversation(conversation)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pinned ? "pin.fill" : "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCurrent ? AppUI.accent : AppUI.label3)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(AppUI.subheadline)
                        .foregroundStyle(AppUI.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(conversation.preview)
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? AppUI.fill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = conversation.title
                renaming = conversation
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button {
                list?.togglePin(conversation)
            } label: {
                Label(conversation.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
            }
            Button {
                list?.duplicate(conversation)
            } label: {
                Label("复制对话", systemImage: "doc.on.doc")
            }
            Button {
                onExportConversation(conversation)
            } label: {
                Label("导出为图片", systemImage: "photo.on.rectangle")
            }
            Divider()
            Button(role: .destructive) {
                Haptics.impact(.medium)
                list?.delete(conversation)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                list?.delete(conversation)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 智能体

    @ViewBuilder
    private var agentsSection: some View {
        sectionHeader("智能体", key: .agents, count: agents.count)

        if expandedSection == .agents {
            agentRow(name: "通用", icon: "sparkles", summary: "默认助手，不带额外设定") {
                onSelectAgent(nil)
            }
            ForEach(agents) { agent in
                agentRow(name: agent.name, icon: agent.icon, summary: agent.summary) {
                    onSelectAgent(agent)
                }
            }
        }
    }

    private func agentRow(
        name: String,
        icon: String,
        summary: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppUI.accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(AppUI.fill))

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(AppUI.subheadline)
                        .foregroundStyle(AppUI.label)
                        .lineLimit(1)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(AppUI.caption)
                            .foregroundStyle(AppUI.label3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 技能

    @ViewBuilder
    private var skillsSection: some View {
        sectionHeader("技能", key: .skills, count: skills.count)

        if expandedSection == .skills {
            if skills.isEmpty {
                emptyHint("还没有技能")
            }
            ForEach(skills) { skill in
                Button {
                    Haptics.selectionChanged()
                    onSelectSkill(skill)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: skill.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppUI.accent)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(AppUI.fill))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("/" + skill.slashCommand)
                                .font(AppUI.subheadline)
                                .foregroundStyle(AppUI.label)
                                .lineLimit(1)
                            if !skill.summary.isEmpty {
                                Text(skill.summary)
                                    .font(AppUI.caption)
                                    .foregroundStyle(AppUI.label3)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppUI.separator.opacity(0.5))
                .frame(height: 0.5)

            Button {
                Haptics.impact(.light)
                onNewConversation()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("聊天")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .background(Capsule(style: .continuous).fill(AppUI.accent))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button {
                    Haptics.impact(.light)
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppUI.label2)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .offset(y: 6)
                .accessibilityLabel("设置")
            }
            .padding(.vertical, 10)
        }
        .background(AppUI.canvas)
    }

    // MARK: - 复用件

    private func sectionHeader(_ title: String, key: SectionKey, count: Int) -> some View {
        Button {
            Haptics.selectionChanged()
            withAnimation(AppAnimation.chip) {
                expandedSection = expandedSection == key ? nil : key
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expandedSection == key ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppUI.label3)
                Text(title)
                    .font(AppUI.sectionTitle)
                    .foregroundStyle(AppUI.label2)
                Text("\(count)")
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subLabel(_ text: String) -> some View {
        Text(text)
            .font(AppUI.caption)
            .foregroundStyle(AppUI.label3)
            .padding(.horizontal, 12)
            .padding(.top, 2)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(AppUI.caption)
            .foregroundStyle(AppUI.label3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

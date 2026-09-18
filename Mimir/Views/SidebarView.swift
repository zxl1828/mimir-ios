import SwiftUI
import SwiftData
import UIKit

/// 抽屉式侧边栏：App 名称与新对话、对话记录、智能体、技能、底部入口。
struct SidebarView: View {

    let list: ConversationListViewModel?
    let agents: [AgentDockItem]
    let skills: [Skill]
    let currentConversationID: UUID?

    var onSelectConversation: (Conversation) -> Void
    var onNewConversation: () -> Void
    var onOpenSettings: () -> Void
    var onOpenMemory: () -> Void
    var onOpenDataFlow: () -> Void
    var onOpenMCP: () -> Void
    var onSelectAgent: (AgentDockItem?) -> Void
    var onSelectSkill: (Skill) -> Void

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
            header
            searchField

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    historySection
                    agentsSection
                    skillsSection
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .liquidGlass(.regular, in: .rect(cornerRadius: 0))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColor.separator.opacity(0.28))
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
            VStack(alignment: .leading, spacing: 1) {
                Text("Mimir")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                Text("本地优先的私人 AI")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Spacer(minLength: 4)

            Button {
                Haptics.impact(.light)
                onNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppColor.accentGradient))
                    .shadow(color: AppColor.brandIndigo.opacity(0.3), radius: 8, y: 3)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.tertiaryText)
            TextField("搜索对话", text: $searchText)
                .textFieldStyle(.plain)
                .font(AppFont.sidebarRow)
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
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassClear(cornerRadius: 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - 对话记录

    @ViewBuilder
    private var historySection: some View {
        sectionHeader("对话记录", key: .history, count: list?.filteredConversations.count ?? 0)

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
                    .foregroundStyle(isCurrent ? AppColor.brandIndigo : AppColor.tertiaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(AppFont.sidebarRow)
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                    Text(conversation.preview)
                        .font(AppFont.chipCompact)
                        .foregroundStyle(AppColor.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? AppColor.brandIndigo.opacity(0.12) : Color.clear)
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
                    .foregroundStyle(AppColor.brandIndigo)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(AppColor.brandIndigo.opacity(0.12)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(AppFont.sidebarRow)
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.tertiaryText)
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
                            .foregroundStyle(AppColor.brandPurple)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(AppColor.brandPurple.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("/" + skill.slashCommand)
                                .font(AppFont.sidebarRow)
                                .foregroundStyle(AppColor.primaryText)
                                .lineLimit(1)
                            if !skill.summary.isEmpty {
                                Text(skill.summary)
                                    .font(AppFont.chipCompact)
                                    .foregroundStyle(AppColor.tertiaryText)
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
                .fill(AppColor.separator.opacity(0.25))
                .frame(height: 0.5)

            VStack(spacing: 2) {
                footerRow("设置", icon: "gearshape") { onOpenSettings() }
                footerRow("记忆浏览器", icon: "brain.head.profile") { onOpenMemory() }
                footerRow("MCP 服务器", icon: "point.3.connected.trianglepath.dotted") { onOpenMCP() }
                footerRow("数据流向", icon: "arrow.left.arrow.right.circle") { onOpenDataFlow() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func footerRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(width: 22)
                Text(title)
                    .font(AppFont.sidebarRow)
                    .foregroundStyle(AppColor.primaryText)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(AppColor.tertiaryText)
                Text(title)
                    .font(AppFont.sidebarSection)
                    .foregroundStyle(AppColor.secondaryText)
                Text("\(count)")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.tertiaryText)
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
            .font(AppFont.chipCompact)
            .foregroundStyle(AppColor.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 2)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(AppFont.chipCompact)
            .foregroundStyle(AppColor.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

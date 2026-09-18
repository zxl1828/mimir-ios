import SwiftUI
import SwiftData
import UIKit

/// 智能体管理：查看内置胶囊、创建与编辑自定义胶囊。
struct AgentManagerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AgentDockItem.sortIndex) private var agents: [AgentDockItem]
    @Query(sort: \Skill.sortIndex) private var skills: [Skill]

    @State private var draft: AgentDraft?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(agents) { agent in
                        Button {
                            draft = AgentDraft(agent: agent)
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: agent.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(agent.tintColor)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(agent.tintColor.opacity(0.13)))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(agent.name)
                                            .font(AppFont.sidebarRow)
                                            .foregroundStyle(AppColor.primaryText)
                                        if agent.isBuiltin {
                                            Text("内置")
                                                .font(AppFont.chipCompact)
                                                .foregroundStyle(AppColor.tertiaryText)
                                        }
                                    }
                                    Text(agent.summary)
                                        .font(AppFont.chipCompact)
                                        .foregroundStyle(AppColor.tertiaryText)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColor.tertiaryText)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if !agent.isBuiltin {
                                Button(role: .destructive) {
                                    modelContext.delete(agent)
                                    try? modelContext.save()
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("智能体胶囊")
                } footer: {
                    Text("胶囊会出现在输入框上方的快捷栏里，切换胶囊即切换当前对话的智能体上下文。")
                }
            }
            .navigationTitle("智能体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft = AgentDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建智能体")
                }
            }
            .sheet(item: $draft) { value in
                AgentEditorView(draft: value, allSkills: skills) { saved in
                    persist(saved)
                }
            }
        }
    }

    private func persist(_ saved: AgentDraft) {
        if let existing = saved.existing {
            existing.name = saved.name
            existing.icon = saved.icon
            existing.summary = saved.summary
            existing.systemPrompt = saved.systemPrompt
            existing.skillNames = Array(saved.skillNames)
            existing.mcpToolNames = saved.mcpToolNames
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            existing.allowsToolDataUpload = saved.allowsUpload
        } else {
            let agent = AgentDockItem(
                name: saved.name,
                icon: saved.icon,
                summary: saved.summary,
                systemPrompt: saved.systemPrompt,
                isBuiltin: false,
                skillNames: Array(saved.skillNames),
                mcpToolNames: saved.mcpToolNames
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                allowsToolDataUpload: saved.allowsUpload,
                sortIndex: (agents.map(\.sortIndex).max() ?? 0) + 1
            )
            modelContext.insert(agent)
        }
        try? modelContext.save()
        Haptics.notify(.success)
    }
}

/// 编辑用的草稿模型。
struct AgentDraft: Identifiable {
    var id = UUID()
    var existing: AgentDockItem?
    var name: String = ""
    var icon: String = "person.crop.circle"
    var summary: String = ""
    var systemPrompt: String = ""
    var skillNames: Set<String> = []
    var mcpToolNames: String = ""
    var allowsUpload: Bool = false

    init() {}

    init(agent: AgentDockItem) {
        existing = agent
        name = agent.name
        icon = agent.icon
        summary = agent.summary
        systemPrompt = agent.systemPrompt
        skillNames = Set(agent.skillNames)
        mcpToolNames = agent.mcpToolNames.joined(separator: ", ")
        allowsUpload = agent.allowsToolDataUpload
    }
}

struct AgentEditorView: View {

    @State var draft: AgentDraft
    let allSkills: [Skill]
    var onSave: (AgentDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private let iconOptions = [
        "person.crop.circle", "ladybug.fill", "list.bullet.rectangle.portrait.fill",
        "character.bubble.fill", "brain", "hammer.fill", "doc.text.magnifyingglass",
        "chart.line.uptrend.xyaxis", "graduationcap.fill", "paintbrush.pointed.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $draft.name)
                    TextField("一句话简介", text: $draft.summary)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { symbol in
                            Button {
                                Haptics.selectionChanged()
                                draft.icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 18))
                                    .foregroundStyle(draft.icon == symbol ? .white : AppColor.secondaryText)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        Circle().fill(draft.icon == symbol
                                                      ? AnyShapeStyle(AppColor.accentGradient)
                                                      : AnyShapeStyle(AppColor.secondaryText.opacity(0.10)))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("系统提示词") {
                    TextEditor(text: $draft.systemPrompt)
                        .frame(minHeight: 130)
                        .font(AppFont.codeSmall)
                }

                Section("关联技能") {
                    if allSkills.isEmpty {
                        Text("还没有可关联的技能")
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    ForEach(allSkills) { skill in
                        Button {
                            Haptics.selectionChanged()
                            if draft.skillNames.contains(skill.name) {
                                draft.skillNames.remove(skill.name)
                            } else {
                                draft.skillNames.insert(skill.name)
                            }
                        } label: {
                            HStack {
                                Image(systemName: skill.icon)
                                    .foregroundStyle(AppColor.brandPurple)
                                Text(skill.name)
                                    .foregroundStyle(AppColor.primaryText)
                                Spacer()
                                if draft.skillNames.contains(skill.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppColor.brandIndigo)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    TextField("例如：repository.read, code.search", text: $draft.mcpToolNames)
                        .font(AppFont.codeSmall)
                    Toggle("允许把这些工具的数据发送到云端", isOn: $draft.allowsUpload)
                } header: {
                    Text("MCP 工具")
                } footer: {
                    Text("默认不允许上传。开启后，该工具返回的数据会作为对话上下文发送到云端接口。")
                }
            }
            .navigationTitle(draft.existing == nil ? "新建智能体" : "编辑智能体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

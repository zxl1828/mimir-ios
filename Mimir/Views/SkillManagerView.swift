import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// 技能管理：浏览、创建、编辑、导入导出、恢复内置技能。
struct SkillManagerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Skill.sortIndex) private var skills: [Skill]

    @State private var editing: SkillDraft?
    @State private var showImporter = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(skills) { skill in
                        Button {
                            editing = SkillDraft(skill: skill)
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: skill.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColor.brandPurple)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(AppColor.brandPurple.opacity(0.12)))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("/" + skill.slashCommand)
                                            .font(AppFont.sidebarRow)
                                            .foregroundStyle(AppColor.primaryText)
                                        if skill.isBuiltin {
                                            Text("内置")
                                                .font(AppFont.chipCompact)
                                                .foregroundStyle(AppColor.tertiaryText)
                                        }
                                        if !skill.isEnabled {
                                            Text("已停用")
                                                .font(AppFont.chipCompact)
                                                .foregroundStyle(AppColor.warning)
                                        }
                                    }
                                    if !skill.summary.isEmpty {
                                        Text(skill.summary)
                                            .font(AppFont.chipCompact)
                                            .foregroundStyle(AppColor.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColor.tertiaryText)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if !skill.isBuiltin {
                                Button(role: .destructive) {
                                    SkillStore.delete(skill, context: modelContext)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            Button {
                                Haptics.impact(.light)
                                if let url = SkillStore.exportDocument(for: skill) {
                                    presentShareSheet([url])
                                }
                            } label: {
                                Label("导出", systemImage: "square.and.arrow.up")
                            }
                            .tint(AppColor.brandIndigo)
                        }
                    }
                } header: {
                    Text("技能")
                } footer: {
                    Text("在输入框里输入 / 可以唤起技能选择器。技能会把自己的提示词前缀叠加到这条消息上。")
                }

                Section {
                    Button("导入技能文件") { showImporter = true }
                    Button("恢复内置技能") {
                        SkillStore.restoreBuiltins(context: modelContext)
                        flash("已恢复内置技能")
                    }
                }
            }
            .navigationTitle("技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = SkillDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建技能")
                }
            }
            .sheet(item: $editing) { draft in
                SkillEditorView(draft: draft) { saved in
                    persist(saved)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(AppFont.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private func persist(_ draft: SkillDraft) {
        if let existing = draft.existing {
            existing.name = draft.name
            existing.slashCommand = draft.slashCommand.isEmpty ? draft.name : draft.slashCommand
            existing.icon = draft.icon
            existing.summary = draft.summary
            existing.promptPrefix = draft.promptPrefix
            existing.triggerKeywords = draft.keywords
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            existing.intentLabel = draft.intentLabel
            existing.isEnabled = draft.isEnabled
            existing.updatedAt = Date()
            try? modelContext.save()
        } else {
            SkillStore.create(
                name: draft.name,
                slashCommand: draft.slashCommand.isEmpty ? draft.name : draft.slashCommand,
                icon: draft.icon,
                summary: draft.summary,
                promptPrefix: draft.promptPrefix,
                triggerKeywords: draft.keywords
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                intentLabel: draft.intentLabel,
                toolNames: [],
                context: modelContext
            )
        }
        Haptics.notify(.success)
        flash(draft.existing == nil ? "技能已创建" : "技能已更新")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            switch SkillStore.importDocument(from: url, context: modelContext) {
            case .added(let count):
                Haptics.notify(.success)
                flash("已导入 \(count) 个技能")
            case .failure(let reason):
                Haptics.notify(.error)
                flash(reason)
            }
        case .failure(let error):
            flash("导入失败：\(error.localizedDescription)")
        }
    }

    private func flash(_ text: String) {
        withAnimation(AppAnimation.chip) { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(AppAnimation.chip) { notice = nil }
        }
    }
}

struct SkillDraft: Identifiable {
    var id = UUID()
    var existing: Skill?
    var name: String = ""
    var slashCommand: String = ""
    var icon: String = "wand.and.stars"
    var summary: String = ""
    var promptPrefix: String = ""
    var keywords: String = ""
    var intentLabel: String = ""
    var isEnabled: Bool = true

    init() {}

    init(skill: Skill) {
        existing = skill
        name = skill.name
        slashCommand = skill.slashCommand
        icon = skill.icon
        summary = skill.summary
        promptPrefix = skill.promptPrefix
        keywords = skill.triggerKeywords.joined(separator: ", ")
        intentLabel = skill.intentLabel
        isEnabled = skill.isEnabled
    }
}

struct SkillEditorView: View {

    @State var draft: SkillDraft
    var onSave: (SkillDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $draft.name)
                    TextField("斜杠命令（不含 /）", text: $draft.slashCommand)
                        .textInputAutocapitalization(.never)
                    TextField("一句话说明", text: $draft.summary)
                    TextField("图标（SF Symbol 名称）", text: $draft.icon)
                        .textInputAutocapitalization(.never)
                        .font(AppFont.codeSmall)
                }

                Section {
                    TextEditor(text: $draft.promptPrefix)
                        .frame(minHeight: 120)
                        .font(AppFont.codeSmall)
                } header: {
                    Text("提示词前缀")
                } footer: {
                    Text("激活技能后，这段文字会加在这条消息的系统提示词里。")
                }

                Section {
                    TextField("用逗号分隔，例如：总结, 摘要, 归纳", text: $draft.keywords)
                    TextField("意图标签（英文，例如 summarize）", text: $draft.intentLabel)
                        .textInputAutocapitalization(.never)
                        .font(AppFont.codeSmall)
                    Toggle("启用这个技能", isOn: $draft.isEnabled)
                } header: {
                    Text("意图识别")
                } footer: {
                    Text("触发关键词用于离线快速匹配；意图标签用于端侧语义分类，只在设备支持时启用。")
                }
            }
            .navigationTitle(draft.existing == nil ? "新建技能" : "编辑技能")
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

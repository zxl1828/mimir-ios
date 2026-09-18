import SwiftUI
import SwiftData
import UIKit

/// 定时任务管理：到点自动用指定智能体生成内容，结果存成新对话。
struct ScheduledTasksView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduledTask.createdAt) private var tasks: [ScheduledTask]
    @Query(sort: \AgentDockItem.sortIndex) private var agents: [AgentDockItem]
    @Query(sort: \Skill.sortIndex) private var skills: [Skill]

    @State private var draft: ScheduledTaskDraft?
    @State private var runningTaskID: UUID?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if tasks.isEmpty {
                        Text("还没有定时任务")
                            .font(AppFont.hint)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                    .onDelete { offsets in
                        for index in offsets where tasks.indices.contains(index) {
                            modelContext.delete(tasks[index])
                        }
                        try? modelContext.save()
                        reschedule()
                    }
                } header: {
                    Text("任务")
                } footer: {
                    Text("任务由系统在后台唤醒执行，实际触发时间可能有几分钟到半小时的偏差；结果会以新对话的形式出现在列表里。")
                }
            }
            .navigationTitle("定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft = ScheduledTaskDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建定时任务")
                }
            }
            .sheet(item: $draft) { value in
                ScheduledTaskEditorView(draft: value, agents: agents, skills: skills) { saved in
                    persist(saved)
                }
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(AppFont.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 22)
                }
            }
        }
    }

    // MARK: - 行

    private func taskRow(_ task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { newValue in
                        task.isEnabled = newValue
                        try? modelContext.save()
                        reschedule()
                    }
                ))
                .labelsHidden()
            }

            HStack(spacing: 10) {
                Label(task.scheduleDescription, systemImage: "clock")
                if !task.agentName.isEmpty {
                    Label(task.agentName, systemImage: "person.crop.circle")
                }
            }
            .font(AppFont.chipCompact)
            .foregroundStyle(AppColor.secondaryText)

            if task.isEnabled, let next = task.nextFireDate() {
                Text("下次运行：\(next.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.brandIndigo)
            }

            if !task.lastError.isEmpty {
                Text(task.lastError)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.danger)
                    .lineLimit(2)
            } else if let last = task.lastRunAt {
                Text("上次运行：\(last.formatted(date: .abbreviated, time: .shortened)) · 累计 \(task.runCount) 次")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await runNow(task) }
                } label: {
                    HStack(spacing: 4) {
                        if runningTaskID == task.id {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 10))
                        }
                        Text(runningTaskID == task.id ? "运行中…" : "立即运行")
                    }
                    .font(AppFont.chipCompact)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppColor.accentGradient))
                }
                .buttonStyle(.plain)
                .disabled(runningTaskID != nil)

                Button {
                    draft = ScheduledTaskDraft(task: task)
                } label: {
                    Text("编辑")
                        .font(AppFont.chipCompact)
                        .foregroundStyle(AppColor.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppColor.secondaryText.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 行为

    private func persist(_ saved: ScheduledTaskDraft) {
        let mask = saved.weekdayMask == 0 ? ScheduledTask.everydayMask : saved.weekdayMask
        if let existing = saved.existing {
            existing.title = saved.title
            existing.prompt = saved.prompt
            existing.agentName = saved.agentName
            existing.skillName = saved.skillName
            existing.thinkingMode = saved.thinkingMode
            existing.hour = saved.hour
            existing.minute = saved.minute
            existing.weekdayMask = mask
            existing.isEnabled = saved.isEnabled
        } else {
            let task = ScheduledTask(
                title: saved.title,
                prompt: saved.prompt,
                agentName: saved.agentName,
                skillName: saved.skillName,
                thinkingMode: saved.thinkingMode,
                hour: saved.hour,
                minute: saved.minute,
                weekdayMask: mask,
                isEnabled: saved.isEnabled
            )
            modelContext.insert(task)
        }
        try? modelContext.save()
        reschedule()
        Haptics.notify(.success)
    }

    private func runNow(_ task: ScheduledTask) async {
        runningTaskID = task.id
        defer { runningTaskID = nil }
        let ok = await ScheduledTaskRunner.run(task, context: modelContext, settings: settings)
        flash(ok ? "已生成，可在对话列表查看" : (task.lastError.isEmpty ? "运行失败" : task.lastError))
        if ok { Haptics.notify(.success) } else { Haptics.notify(.error) }
    }

    private func reschedule() {
        BackgroundTaskScheduler.reschedule(tasks: tasks)
    }

    private func flash(_ text: String) {
        withAnimation(AppAnimation.chip) { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(AppAnimation.chip) { notice = nil }
        }
    }
}

// MARK: - 草稿与编辑

struct ScheduledTaskDraft: Identifiable {
    var id = UUID()
    var existing: ScheduledTask?
    var title: String = ""
    var prompt: String = ""
    var agentName: String = ""
    var skillName: String = ""
    var thinkingMode: ThinkingMode = .thinking
    var hour: Int = 8
    var minute: Int = 0
    var weekdayMask: Int = ScheduledTask.everydayMask
    var isEnabled: Bool = true

    init() {}

    init(task: ScheduledTask) {
        existing = task
        id = task.id
        title = task.title
        prompt = task.prompt
        agentName = task.agentName
        skillName = task.skillName
        thinkingMode = task.thinkingMode
        hour = task.hour
        minute = task.minute
        weekdayMask = task.weekdayMask
        isEnabled = task.isEnabled
    }
}

struct ScheduledTaskEditorView: View {

    @State var draft: ScheduledTaskDraft
    let agents: [AgentDockItem]
    let skills: [Skill]
    var onSave: (ScheduledTaskDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("名称，例如「每日简报」", text: $draft.title)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("执行内容")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColor.secondaryText)
                        TextEditor(text: $draft.prompt)
                            .frame(minHeight: 110)
                            .font(AppFont.codeSmall)
                    }
                }

                Section("时间") {
                    DatePicker("触发时间", selection: timeBinding, displayedComponents: .hourAndMinute)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("重复")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColor.secondaryText)

                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { index in
                                Button {
                                    Haptics.selectionChanged()
                                    draft.weekdayMask ^= (1 << index)
                                } label: {
                                    Text(weekdayNames[index])
                                        .font(AppFont.chipCompact)
                                        .foregroundStyle(isSelected(index) ? .white : AppColor.secondaryText)
                                        .frame(width: 34, height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(isSelected(index)
                                                      ? AnyShapeStyle(AppColor.accentGradient)
                                                      : AnyShapeStyle(AppColor.secondaryText.opacity(0.12)))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            presetButton("每天", mask: ScheduledTask.everydayMask)
                            presetButton("工作日", mask: ScheduledTask.weekdayOnlyMask)
                            presetButton("周末", mask: ScheduledTask.weekendMask)
                            Spacer(minLength: 0)
                        }
                    }
                }

                Section("上下文") {
                    Picker("智能体", selection: $draft.agentName) {
                        Text("不指定").tag("")
                        ForEach(agents) { agent in
                            Text(agent.name).tag(agent.name)
                        }
                    }
                    Picker("技能", selection: $draft.skillName) {
                        Text("不指定").tag("")
                        ForEach(skills) { skill in
                            Text(skill.name).tag(skill.name)
                        }
                    }
                    Picker("思考模式", selection: $draft.thinkingMode) {
                        ForEach(ThinkingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section {
                    Toggle("启用这个任务", isOn: $draft.isEnabled)
                } footer: {
                    Text("只有启用的任务会被系统唤醒执行。结果保存成一段新对话，标题带上日期。")
                }
            }
            .navigationTitle(draft.existing == nil ? "新建定时任务" : "编辑定时任务")
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
                    .disabled(
                        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.weekdayMask == 0
                    )
                }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = draft.hour
                components.minute = draft.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.hour = components.hour ?? 8
                draft.minute = components.minute ?? 0
            }
        )
    }

    private func isSelected(_ index: Int) -> Bool {
        draft.weekdayMask & (1 << index) != 0
    }

    private func presetButton(_ title: String, mask: Int) -> some View {
        Button {
            Haptics.selectionChanged()
            draft.weekdayMask = mask
        } label: {
            Text(title)
                .font(AppFont.chipCompact)
                .foregroundStyle(draft.weekdayMask == mask ? AppColor.brandIndigo : AppColor.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(draft.weekdayMask == mask
                              ? AppColor.brandIndigo.opacity(0.14)
                              : AppColor.secondaryText.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}

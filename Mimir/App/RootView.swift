import SwiftUI
import SwiftData

/// 应用根视图：根据引导完成状态决定进入引导页还是主界面，
/// 并负责一次性种子数据与启动期维护任务。
struct RootView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AppSettings()
    @State private var isReady = false

    var body: some View {
        Group {
            if !isReady {
                AuroraBackground(intensity: 0.6, showsParticles: false)
            } else if settings.hasCompletedOnboarding && settings.hasUsableCredential {
                MainChatView()
            } else {
                OnboardingView()
            }
        }
        .environment(settings)
        .preferredColorScheme(nil)
        .task {
            StartupCoordinator.seedIfNeeded(context: modelContext)
            StartupCoordinator.refreshScheduledTasks(context: modelContext)
            isReady = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                StartupCoordinator.performMaintenance(context: modelContext, settings: settings)
            }
        }
    }
}

/// 启动期一次性工作：内置智能体 / 技能种子、按策略清理过期对话。
enum StartupCoordinator {

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        do {
            // 内置技能按名称幂等补齐：新版本新增的内置技能会自动出现，
            // 用户自己改过的同名技能不会被覆盖。
            let existingSkills = try context.fetch(FetchDescriptor<Skill>())
            let existingSkillNames = Set(existingSkills.map(\.name))
            var nextSkillIndex = (existingSkills.map(\.sortIndex).max() ?? -1) + 1
            for skill in Skill.builtinSeeds() where !existingSkillNames.contains(skill.name) {
                skill.sortIndex = nextSkillIndex
                nextSkillIndex += 1
                context.insert(skill)
            }

            let agentCount = try context.fetchCount(FetchDescriptor<AgentDockItem>())
            if agentCount == 0 {
                for agent in AgentDockItem.builtinSeeds() {
                    context.insert(agent)
                }
            }

            let taskCount = try context.fetchCount(FetchDescriptor<ScheduledTask>())
            if taskCount == 0 {
                context.insert(
                    ScheduledTask(
                        title: "每日简报",
                        prompt: "请生成今天的简报：先用一句话概括今天，再给出三条值得关注的提醒（工作安排、待办梳理、效率建议）。",
                        thinkingMode: .quick,
                        hour: 8,
                        minute: 0,
                        isEnabled: false
                    )
                )
            }

            if context.hasChanges { try context.save() }
        } catch {
            // 种子数据失败不应阻断启动，下一次启动会重试。
        }
    }

    /// 冷启动时把下一次后台唤醒重新排上。
    @MainActor
    static func refreshScheduledTasks(context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<ScheduledTask>())) ?? []
        BackgroundTaskScheduler.reschedule(tasks: tasks)
    }

    @MainActor
    static func performMaintenance(context: ModelContext, settings: AppSettings) {
        guard let cutoff = settings.retention.cutoff else { return }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.isPinned == false }
        )
        guard let conversations = try? context.fetch(descriptor) else { return }
        var removed = false
        for conversation in conversations where conversation.usesAutoDelete {
            if conversation.updatedAt < cutoff {
                context.delete(conversation)
                removed = true
            }
        }
        if removed { try? context.save() }
    }
}

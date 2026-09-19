import SwiftUI
import SwiftData

@main
struct MimirApp: App {

    /// 所有持久化模型都在这里注册，Schema 变更时只需改这一处。
    private let container: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            ChatMessage.self,
            MemoryEntry.self,
            Skill.self,
            AgentDockItem.self,
            MCPServerConfig.self,
            ScheduledTask.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 本地库损坏时退回内存库，保证 App 仍可启动而不是直接崩溃。
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }

    init() {
        AppContainer.shared = container
        // 崩溃与步骤日志：语音模式闪退这类问题靠它定位。
        AppDiagnostics.install()
        // 后台任务必须在启动早期注册，否则系统会拒绝调度。
        BackgroundTaskScheduler.register()
        BackgroundTaskScheduler.scheduleAppRefresh()
    }
}

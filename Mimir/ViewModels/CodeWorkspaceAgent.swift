import Foundation
import Observation

struct CodeAgentTurn: Identifiable {
    enum Kind {
        case user
        case assistant
        case activity
    }

    let id = UUID()
    let kind: Kind
    var text: String
    /// 思考过程。正常对话里能看到的推演，这里也要能看到，不分两套逻辑。
    var reasoning: String = ""
    var isStreaming: Bool = false
    /// 这条活动是否真的改动了文件，界面上用它决定要不要标成"已写入"。
    var didWriteFile: Bool = false
}

/// 代码页的对话引擎。
///
/// 定位很明确：**它就是一个普通对话**——同样的流式输出、同样的思考过程、同样的
/// 多轮工具调用。唯一的区别是它的工具落在工作区文件夹上，于是对话过程中被改写的
/// 源码可以实时出现在上方的编辑器里（`liveFilePath` / `liveContent`）。
@MainActor
@Observable
final class CodeWorkspaceAgent {
    private(set) var turns: [CodeAgentTurn] = []
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    /// 最近一次被改写的文件（相对路径）与它的最新内容，供编辑器实时展示。
    private(set) var liveFilePath: String?
    private(set) var liveContent: String = ""
    /// 本轮对话的编辑统计分桶，交给 `FileEditSummaryCard` 显示。
    private(set) var runID: UUID?

    private var cancelRequested = false

    private var context: [LLMChatMessage] = [
        LLMChatMessage(role: .system, text: """
        你是 Mimir 手机端代码 Agent。用户选定的本地工作区是唯一可访问目录。
        先用 workspace_list 找文件；需要时用 workspace_read 读取；仅按用户要求通过 workspace_write 修改或新建文件。
        工作区支持 Swift、Python、JavaScript/TypeScript、C/C++、Rust、Go、Java、Kotlin、Dart、PHP、Ruby、Shell、配置文件、Markdown 以及常见的纯文本工程文件；不要因为扩展名不熟悉就拒绝读取，先尝试按文本处理。
        写文件时必须提供完整文本内容。不得声称运行过 shell、测试或编译；编译只能由页面的 GitHub Actions 按钮执行。
        只处理与用户请求相关的文件，修改后说明文件路径和关键变化。遇到不明确或可能覆盖用户重要内容时先询问。
        """)
    ]

    /// 用户点"停止"。
    func cancel() {
        cancelRequested = true
    }

    func reset() {
        turns.removeAll()
        errorMessage = nil
        liveFilePath = nil
        liveContent = ""
        runID = nil
        FileEditLedger.shared.activeRunID = nil
    }

    func send(_ prompt: String, workspace: WorkspaceManager, settings: AppSettings) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        guard workspace.activeWorkspaceURL != nil else {
            turns.append(CodeAgentTurn(kind: .activity, text: "请先选择一个工作区文件夹。"))
            return
        }

        let credential = settings.resolvedCredential
        guard !credential.key.isEmpty else {
            turns.append(CodeAgentTurn(kind: .activity, text: "请先在设置中配置模型 API Key。"))
            return
        }

        errorMessage = nil
        isWorking = true
        cancelRequested = false

        let run = UUID()
        runID = run
        FileEditLedger.shared.activeRunID = run

        turns.append(CodeAgentTurn(kind: .user, text: trimmed))
        let assistantIndex = turns.count
        turns.append(CodeAgentTurn(kind: .assistant, text: "", isStreaming: true))
        context.append(LLMChatMessage(role: .user, text: trimmed))
        if context.count > 24 {
            context = [context[0]] + Array(context.suffix(20))
        }

        var parameters = settings.parameters
        parameters.modelID = credential.modelID
        parameters.maxTokens = min(parameters.maxTokens, 4_096)
        let client = LLMClientFactory.make(for: credential)
        var workingMessages = context

        do {
            for _ in 0..<8 {
                if cancelRequested { break }
                var responseText = ""
                var reasoning = ""
                var calls: [LLMToolCall] = []
                let stream = client.streamChat(
                    messages: workingMessages,
                    parameters: parameters,
                    credential: credential,
                    tools: Self.tools
                )
                for try await event in stream {
                    if cancelRequested { break }
                    switch event {
                    case .textDelta(let text):
                        responseText += text
                        turns[assistantIndex].text = responseText
                    case .reasoningDelta(let delta):
                        reasoning += delta
                        turns[assistantIndex].reasoning = reasoning
                    case .toolCallsReady(let ready):
                        calls = ready
                    case .toolCallDelta, .usage, .finished:
                        break
                    }
                }
                if cancelRequested { break }

                guard !calls.isEmpty else {
                    workingMessages.append(LLMChatMessage(role: .assistant, text: responseText))
                    break
                }

                workingMessages.append(LLMChatMessage(role: .assistant, text: responseText, toolCalls: calls))
                for call in calls {
                    if cancelRequested { break }
                    let activityIndex = turns.count
                    turns.append(CodeAgentTurn(kind: .activity, text: Self.activityLabel(for: call)))
                    let result: String
                    do {
                        result = try await Self.invoke(call, workspace: workspace)
                        turns[activityIndex].text += " · 完成"
                        if call.name == "workspace_write" {
                            turns[activityIndex].didWriteFile = true
                            turns[assistantIndex].text = responseText
                            if let written = Self.writtenPath(in: call) {
                                await presentLiveSource(path: written, workspace: workspace)
                            }
                        }
                    } catch {
                        result = "工具执行失败：\(error.localizedDescription)"
                        turns[activityIndex].text += " · 失败"
                    }
                    workingMessages.append(
                        LLMChatMessage(role: .tool, text: String(result.prefix(32_000)), toolCallID: call.id, toolName: call.name)
                    )
                }
            }
            context = workingMessages
        } catch {
            errorMessage = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            turns[assistantIndex].text = errorMessage ?? "请求失败。"
        }

        turns[assistantIndex].isStreaming = false
        if turns[assistantIndex].text.isEmpty, errorMessage == nil {
            turns[assistantIndex].text = cancelRequested ? "已停止。" : "Agent 已完成文件操作。"
        }
        isWorking = false
        FileEditLedger.shared.activeRunID = nil
    }

    /// 把刚写完的文件推给编辑器：用户看到的源码就是模型刚改出来的那份。
    private func presentLiveSource(path: String, workspace: WorkspaceManager) async {
        liveFilePath = path
        liveContent = (try? await workspace.readWorkspaceText(path: path)) ?? ""
        if let item = workspace.sourceFiles.first(where: { workspace.relativePath(for: $0) == path }) {
            workspace.selectCodeFile(item)
        }
    }

    private static func writtenPath(in call: LLMToolCall) -> String? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return arguments["path"] as? String
    }

    private static let tools: [LLMToolDefinition] = [
        LLMToolDefinition(
            name: "workspace_list",
            description: "列出当前工作区内可编辑的源代码、配置和纯文本文件相对路径。",
            parametersJSON: #"{"type":"object","properties":{},"additionalProperties":false}"#
        ),
        LLMToolDefinition(
            name: "workspace_read",
            description: "读取当前工作区内一个文本文件，支持常见代码和配置编码。",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}"#
        ),
        LLMToolDefinition(
            name: "workspace_write",
            description: "在当前工作区内创建或完整覆盖一个文本文件。",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"],"additionalProperties":false}"#
        )
    ]

    private static func invoke(_ call: LLMToolCall, workspace: WorkspaceManager) async throws -> String {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkspaceAccessError.invalidPath
        }

        switch call.name {
        case "workspace_list":
            let paths = workspace.sourceFiles.compactMap(workspace.relativePath(for:))
            return paths.isEmpty ? "工作区没有可编辑的源文件。" : paths.joined(separator: "\n")
        case "workspace_read":
            guard let path = arguments["path"] as? String else { throw WorkspaceAccessError.invalidPath }
            return try await workspace.readWorkspaceText(path: path)
        case "workspace_write":
            guard let path = arguments["path"] as? String,
                  let content = arguments["content"] as? String else { throw WorkspaceAccessError.invalidPath }
            try await workspace.writeWorkspaceText(path: path, content: content)
            return "已保存 \(path)（\(content.utf8.count) bytes）。"
        default:
            throw WorkspaceAccessError.invalidPath
        }
    }

    private static func activityLabel(for call: LLMToolCall) -> String {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "执行 \(call.name)"
        }
        let path = arguments["path"] as? String
        switch call.name {
        case "workspace_list": return "检查工作区文件"
        case "workspace_read": return "读取 \(path ?? "文件")"
        case "workspace_write": return "写入 \(path ?? "文件")"
        default: return "执行 \(call.name)"
        }
    }
}

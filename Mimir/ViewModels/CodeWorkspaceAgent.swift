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
}

@MainActor
@Observable
final class CodeWorkspaceAgent {
    private(set) var turns: [CodeAgentTurn] = []
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    private var context: [LLMChatMessage] = [
        LLMChatMessage(role: .system, text: """
        你是 Mimir 手机端代码 Agent。用户选定的本地工作区是唯一可访问目录。
        先用 workspace_list 找文件；需要时用 workspace_read 读取；仅按用户要求通过 workspace_write 修改或新建文件。
        写文件时必须提供完整 UTF-8 文件内容。不得声称运行过 shell、测试或编译；编译只能由页面的 GitHub Actions 按钮执行。
        只处理与用户请求相关的文件，修改后说明文件路径和关键变化。遇到不明确或可能覆盖用户重要内容时先询问。
        """)
    ]

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
        turns.append(CodeAgentTurn(kind: .user, text: trimmed))
        let assistantIndex = turns.count
        turns.append(CodeAgentTurn(kind: .assistant, text: ""))
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
            for _ in 0..<5 {
                var responseText = ""
                var calls: [LLMToolCall] = []
                let stream = client.streamChat(
                    messages: workingMessages,
                    parameters: parameters,
                    credential: credential,
                    tools: Self.tools
                )
                for try await event in stream {
                    switch event {
                    case .textDelta(let text):
                        responseText += text
                        turns[assistantIndex].text = responseText
                    case .toolCallsReady(let ready):
                        calls = ready
                    case .reasoningDelta, .toolCallDelta, .usage, .finished:
                        break
                    }
                }

                guard !calls.isEmpty else {
                    workingMessages.append(LLMChatMessage(role: .assistant, text: responseText))
                    break
                }

                workingMessages.append(LLMChatMessage(role: .assistant, text: responseText, toolCalls: calls))
                for call in calls {
                    let activityIndex = turns.count
                    turns.append(CodeAgentTurn(kind: .activity, text: Self.activityLabel(for: call)))
                    let result: String
                    do {
                        result = try Self.invoke(call, workspace: workspace)
                        turns[activityIndex].text += " · 完成"
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
        if turns[assistantIndex].text.isEmpty, errorMessage == nil {
            turns[assistantIndex].text = "Agent 已完成文件操作。"
        }
        isWorking = false
    }

    private static let tools: [LLMToolDefinition] = [
        LLMToolDefinition(
            name: "workspace_list",
            description: "列出当前手机工作区中的可编辑源文件相对路径。",
            parametersJSON: #"{"type":"object","properties":{},"additionalProperties":false}"#
        ),
        LLMToolDefinition(
            name: "workspace_read",
            description: "读取当前工作区内一个 UTF-8 文本文件。",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}"#
        ),
        LLMToolDefinition(
            name: "workspace_write",
            description: "在当前工作区内创建或完整覆盖一个 UTF-8 文本文件。",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"],"additionalProperties":false}"#
        )
    ]

    private static func invoke(_ call: LLMToolCall, workspace: WorkspaceManager) throws -> String {
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
            return try workspace.readWorkspaceText(path: path)
        case "workspace_write":
            guard let path = arguments["path"] as? String,
                  let content = arguments["content"] as? String else { throw WorkspaceAccessError.invalidPath }
            try workspace.writeWorkspaceText(path: path, content: content)
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

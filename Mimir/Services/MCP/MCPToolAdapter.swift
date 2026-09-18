import Foundation

/// 把 MCP 工具转换为模型可调用的函数定义。
enum MCPToolAdapter {

    /// 只有服务器配置允许上传数据时，工具返回值才会进入对话上下文。
    static func definitions(from tools: [MCPToolDescriptor]) -> [LLMToolDefinition] {
        tools.map { tool in
            LLMToolDefinition(
                name: tool.name,
                description: tool.summary.isEmpty ? tool.displayName : tool.summary,
                parametersJSON: tool.schemaJSON
            )
        }
    }

    /// 把工具定义转成 OpenAI 兼容请求里的 tools 数组（JSON 文本）。
    static func openAIToolsJSON(_ tools: [LLMToolDefinition]) -> String? {
        guard !tools.isEmpty else { return nil }
        let payload = tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": Self.jsonObject(from: tool.parametersJSON) ?? ["type": "object"]
                ]
            ] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

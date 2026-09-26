import Foundation

/// 模型目录：对话内快速切换用（设置页仍可填任意模型 ID）。
enum ModelCatalog {

    struct Option: Identifiable, Hashable {
        var id: String
        var title: String
    }

    /// 按当前凭据的协议类型给出候选模型；用户自己填过的模型 ID 永远排在第一位。
    static func options(for credential: APICredential, customModels: [CustomModelEntry] = []) -> [Option] {
        var list: [Option]
        switch credential.format.providerKind {
        case .openAICompatible:
            list = [
                Option(id: "deepseek-chat", title: "deepseek-chat · 快速对话"),
                Option(id: "deepseek-reasoner", title: "deepseek-reasoner · 深度推理")
            ]
        case .anthropic:
            list = [
                Option(id: "claude-sonnet-4-5", title: "claude-sonnet-4-5"),
                Option(id: "claude-haiku-4-5", title: "claude-haiku-4-5")
            ]
        }

        let extras = customModels.map { Option(id: $0.modelID, title: $0.displayName) }
        list.append(contentsOf: extras)

        let current = credential.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !list.contains(where: { $0.id == current }) {
            list.insert(Option(id: current, title: current), at: 0)
        }
        // 去重（同一模型 ID 只留一个）
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// 顶栏胶囊里的短标签，尽量不超过 8 个字符。
    static func shortLabel(for modelID: String) -> String {
        switch modelID {
        case "deepseek-chat": return "Chat"
        case "deepseek-reasoner": return "Reasoner"
        case "claude-sonnet-4-5": return "Sonnet"
        case "claude-haiku-4-5": return "Haiku"
        default:
            let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "未选模型" }
            return trimmed.count > 10 ? String(trimmed.prefix(9)) + "…" : trimmed
        }
    }

}

import Foundation

/// Codex / Claude 技能包的载体。
///
/// 这 11 个 `SKILL.md` 原文放在 `Resources/CodexSkillPack.json` 里随 App 一起打包，
/// 首次启动由 `SkillStore.installCodexPack` 写进 SwiftData。
///
/// 早先我把它们编成了 236KB 的 Swift 字符串字面量，结果 Xcode 编译这一步
/// 会连续跑十几分钟然后被杀掉（日志里一条诊断都没有，只有 exit code 65）。
/// 改成资源文件后编译器彻底不用碰这批文本。
enum CodexSkillPack {

    struct Entry: Hashable {
        let name: String
        let markdown: String
    }

    private struct Payload: Decodable {
        let schemaVersion: Int
        let entries: [Item]

        struct Item: Decodable {
            let name: String
            let markdown: String
        }
    }

    /// 解析失败返回空数组：技能包装不上时 App 照常启动，只是少了这批技能。
    static let entries: [Entry] = load()

    private static func load() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "CodexSkillPack", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return [] }
        return payload.entries.map { Entry(name: $0.name, markdown: $0.markdown) }
    }
}

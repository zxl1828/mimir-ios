import Foundation
import NaturalLanguage

/// 意图感知与技能推荐。
///
/// 双层策略：先做纯离线的关键词匹配（毫秒级，永远可用），
/// 再用端侧语言模型做一次语义意图分类来补充与校正。
@MainActor
final class IntentRecommender {

    struct Recommendation: Equatable {
        var skillName: String
        var confidence: Double
        var reason: String
    }

    private var semanticCache: [String: (label: String, at: Date)] = [:]
    private let cacheLifetime: TimeInterval = 120

    /// 关键词匹配（同步、离线、毫秒级）。
    func keywordRecommendation(for text: String, skills: [Skill]) -> Recommendation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }

        let lowercased = trimmed.lowercased()
        let tokens = Self.contentTokens(in: trimmed)
        var best: (skill: Skill, score: Double)?

        for skill in skills where skill.isEnabled {
            guard !skill.triggerKeywords.isEmpty else { continue }

            var hits = 0.0
            for keyword in skill.triggerKeywords {
                let needle = keyword.lowercased()
                if lowercased.contains(needle) {
                    // 长关键词更具体，权重更高。
                    hits += 1 + Double(min(needle.count, 8)) / 20
                } else if tokens.contains(needle) {
                    hits += 0.8
                }
            }
            guard hits > 0 else { continue }

            let coverage = hits / (Double(skill.triggerKeywords.count) + 1.5)
            let score = min(coverage * 1.8, 1.0)
            if best == nil || score > best!.score {
                best = (skill, score)
            }
        }

        guard let best, best.score >= Self.keywordThreshold else { return nil }
        return Recommendation(
            skillName: best.skill.name,
            confidence: best.score,
            reason: "关键词匹配"
        )
    }

    /// 端侧语义意图分类（Foundation Models）。不可用时静默返回 nil。
    func semanticRecommendation(for text: String, skills: [Skill]) async -> Recommendation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }

        let candidates = skills.filter { $0.isEnabled && !$0.intentLabel.isEmpty }
        guard candidates.count >= 2 else { return nil }

        if let cached = semanticCache[trimmed], Date().timeIntervalSince(cached.at) < cacheLifetime {
            guard let match = candidates.first(where: { $0.intentLabel == cached.label }) else { return nil }
            return Recommendation(skillName: match.name, confidence: 0.72, reason: "语义意图")
        }

        let labels = candidates.map { "\($0.intentLabel)=\($0.name)" }.joined(separator: ", ")
        let prompt = """
        用户输入：\(trimmed)

        可选的意图标签：\(labels)

        请只输出最匹配的一个标签名（等号左边部分），不要解释。如果都不匹配，输出 none。
        """

        guard let label = await OnDeviceLanguageModel.classify(prompt: prompt) else { return nil }
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        semanticCache[trimmed] = (normalized, Date())

        guard normalized != "none",
              let match = candidates.first(where: { $0.intentLabel.lowercased() == normalized }) else {
            return nil
        }

        return Recommendation(skillName: match.name, confidence: 0.75, reason: "语义意图")
    }

    /// 组合推荐：关键词优先出结果，语义结果在有把握时覆盖。
    func recommend(for text: String, skills: [Skill]) async -> Recommendation? {
        let keyword = keywordRecommendation(for: text, skills: skills)
        let semantic = await semanticRecommendation(for: text, skills: skills)

        switch (keyword, semantic) {
        case (nil, nil):
            return nil
        case (let value?, nil):
            return value.confidence >= Self.keywordThreshold ? value : nil
        case (nil, let value?):
            return value.confidence >= Self.semanticThreshold ? value : nil
        case (let keyword?, let semantic?):
            if keyword.skillName == semantic.skillName {
                return Recommendation(
                    skillName: keyword.skillName,
                    confidence: min(0.97, keyword.confidence + 0.15),
                    reason: "关键词 + 语义一致"
                )
            }
            return semantic.confidence >= 0.8 ? semantic : keyword
        }
    }

    static let keywordThreshold: Double = 0.34
    static let semanticThreshold: Double = 0.7

    /// 用 NLTagger 抽实词，避免用整句做子串匹配。
    static func contentTokens(in text: String) -> Set<String> {
        var tokens: Set<String> = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            guard let tag else { return true }
            switch tag {
            case .noun, .verb, .adjective, .adverb:
                let token = String(text[range]).lowercased()
                if token.count >= 2 { tokens.insert(token) }
            default:
                break
            }
            return true
        }
        return tokens
    }
}

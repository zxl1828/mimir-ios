import Foundation

struct ModelPrice: Sendable {
    let inputUSDPerMillion: Double
    let outputUSDPerMillion: Double
    var longPromptThreshold: Int? = nil
    var longPromptInputUSDPerMillion: Double? = nil
    var longPromptOutputUSDPerMillion: Double? = nil

    func costUSD(promptTokens: Int, outputTokens: Int) -> Double {
        let usesLongPromptPrice = longPromptThreshold.map { promptTokens > $0 } ?? false
        let inputRate = usesLongPromptPrice ? longPromptInputUSDPerMillion ?? inputUSDPerMillion : inputUSDPerMillion
        let outputRate = usesLongPromptPrice ? longPromptOutputUSDPerMillion ?? outputUSDPerMillion : outputUSDPerMillion
        return (Double(max(promptTokens, 0)) * inputRate + Double(max(outputTokens, 0)) * outputRate) / 1_000_000
    }
}

enum ModelPricingCatalog {
    static let revisionLabel = "参考价更新于 2026-10-31"
    static let sources = [
        URL(string: "https://platform.openai.com/docs/pricing")!,
        URL(string: "https://www.anthropic.com/pricing#api")!,
        URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!,
        URL(string: "https://api-docs.deepseek.com/quick_start/pricing")!
    ]

    private static let prices: [(String, ModelPrice)] = [
        ("gpt-5.6-sol", .init(inputUSDPerMillion: 4.00, outputUSDPerMillion: 20.00)),
        ("gpt-4o-mini", .init(inputUSDPerMillion: 0.15, outputUSDPerMillion: 0.60)),
        ("gpt-4o", .init(inputUSDPerMillion: 2.50, outputUSDPerMillion: 10.00)),
        ("gpt-4.1", .init(inputUSDPerMillion: 2.00, outputUSDPerMillion: 8.00)),
        ("gpt-4.1-mini", .init(inputUSDPerMillion: 0.40, outputUSDPerMillion: 1.60)),
        ("gpt-4.1-nano", .init(inputUSDPerMillion: 0.10, outputUSDPerMillion: 0.40)),
        ("claude-3-5-haiku", .init(inputUSDPerMillion: 0.80, outputUSDPerMillion: 4.00)),
        ("claude-3-7-sonnet", .init(inputUSDPerMillion: 3.00, outputUSDPerMillion: 15.00)),
        ("claude-sonnet-5-5", .init(inputUSDPerMillion: 2.00, outputUSDPerMillion: 10.00)),
        ("claude-opus-5-5", .init(inputUSDPerMillion: 4.00, outputUSDPerMillion: 20.00)),
        ("claude-haiku-5-5", .init(
            inputUSDPerMillion: 0.10,
            outputUSDPerMillion: 0.50,
            longPromptThreshold: 100_000,
            longPromptInputUSDPerMillion: 0.50,
            longPromptOutputUSDPerMillion: 2.50
        )),
        ("claude-opus-4-8", .init(inputUSDPerMillion: 5.00, outputUSDPerMillion: 25.00)),
        ("claude-sonnet-4-6", .init(inputUSDPerMillion: 3.00, outputUSDPerMillion: 15.00)),
        ("claude-opus-4-7", .init(inputUSDPerMillion: 5.00, outputUSDPerMillion: 25.00)),
        ("claude-sonnet-4", .init(inputUSDPerMillion: 3.00, outputUSDPerMillion: 15.00)),
        ("claude-sonnet-4-5", .init(inputUSDPerMillion: 3.00, outputUSDPerMillion: 15.00)),
        ("claude-haiku-4-5", .init(inputUSDPerMillion: 1.00, outputUSDPerMillion: 5.00)),
        ("claude-opus-4", .init(inputUSDPerMillion: 15.00, outputUSDPerMillion: 75.00)),
        ("claude-opus-4-1", .init(inputUSDPerMillion: 15.00, outputUSDPerMillion: 75.00)),
        ("gemini-2.0-flash", .init(inputUSDPerMillion: 0.10, outputUSDPerMillion: 0.40)),
        ("gemini-2.5-flash", .init(inputUSDPerMillion: 0.30, outputUSDPerMillion: 2.50)),
        ("gemini-2.5-pro", .init(
            inputUSDPerMillion: 1.25,
            outputUSDPerMillion: 10.00,
            longPromptThreshold: 200_000,
            longPromptInputUSDPerMillion: 2.50,
            longPromptOutputUSDPerMillion: 15.00
        )),
        ("gemini-3.1-pro-preview", .init(
            inputUSDPerMillion: 2.00,
            outputUSDPerMillion: 12.00,
            longPromptThreshold: 200_000,
            longPromptInputUSDPerMillion: 4.00,
            longPromptOutputUSDPerMillion: 18.00
        )),
        ("deepseek-flash", .init(inputUSDPerMillion: 0.30, outputUSDPerMillion: 1.20)),
        ("deepseek-v4-pro", .init(inputUSDPerMillion: 1.32, outputUSDPerMillion: 3.96)),
        ("deepseek-chat", .init(inputUSDPerMillion: 0.30, outputUSDPerMillion: 1.20)),
        ("deepseek-reasoner", .init(inputUSDPerMillion: 1.32, outputUSDPerMillion: 3.96))
    ]

    static func price(for modelID: String) -> ModelPrice? {
        let lowered = modelID.lowercased()
        let id = lowered.split(separator: "/").last.map(String.init) ?? lowered
        return prices.first(where: { id == $0.0 })?.1
            ?? prices.first(where: { id.hasPrefix($0.0 + "-") })?.1
    }

    static func costUSD(modelID: String, promptTokens: Int, outputTokens: Int) -> Double? {
        guard let price = price(for: modelID) else { return nil }
        return price.costUSD(promptTokens: promptTokens, outputTokens: outputTokens)
    }
}

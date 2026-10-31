import SwiftUI

struct CostTrendCard: View {
    let messages: [ChatMessage]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @AppStorage("mimir.cost.monthlyBudgetUSD") private var monthlyBudgetUSD = 10.0
    @AppStorage("mimir.cost.usdToCNY") private var usdToCNY = 7.2

    private var dailyCosts: [(Date, Double)] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return nil }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let amount = messages.filter { $0.createdAt >= day && $0.createdAt < next }
                .compactMap(\.estimatedCostUSD).reduce(0, +)
            return (day, amount)
        }
    }

    private var thisMonthUSD: Double {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return messages.filter { $0.createdAt >= start }.compactMap(\.estimatedCostUSD).reduce(0, +)
    }

    private var budgetRatio: Double {
        monthlyBudgetUSD > 0 ? thisMonthUSD / monthlyBudgetUSD : 0
    }

    private var budgetLabel: String {
        budgetRatio >= 1
            ? String(format: "已超月预算 · $%.4f / $%.0f", thisMonthUSD, monthlyBudgetUSD)
            : String(format: "%@预算 $%.0f · 已用 %.0f%%", budgetRatio >= 0.8 ? "接近" : "月", monthlyBudgetUSD, budgetRatio * 100)
    }

    private var budgetColor: Color {
        budgetRatio >= 1 ? .orange : (budgetRatio >= 0.8 ? .yellow : accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("API COST / 7 DAYS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("模型调用成本")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.4f", thisMonthUSD))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    Text(String(format: "¥%.3f 本月", thisMonthUSD * usdToCNY))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                let maxCost = max(dailyCosts.map(\.1).max() ?? 0, 0.00001)
                ForEach(Array(dailyCosts.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [accent, Color(hex: "B7A1FF")], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(3, CGFloat(item.1 / maxCost) * 54))
                        Text(item.0.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: 72, alignment: .bottom)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: budgetRatio >= 1 ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent")
                    .foregroundStyle(budgetColor)
                Text(budgetLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(budgetRatio >= 1 || budgetRatio >= 0.8 ? budgetColor : AppUI.textSubtitle(scheme: scheme))
                Spacer(minLength: 0)
                Menu {
                    ForEach([5.0, 10.0, 20.0, 50.0, 100.0], id: \.self) { value in
                        Button(String(format: "$%.0f / 月", value)) { monthlyBudgetUSD = value }
                    }
                    Menu("USD/CNY 汇率") {
                        ForEach([7.0, 7.2, 7.5, 7.8], id: \.self) { rate in
                            Button(String(format: "1 USD = %.2f CNY", rate)) { usdToCNY = rate }
                        }
                    }
                    Divider()
                    Link("OpenAI 定价", destination: ModelPricingCatalog.sources[0])
                    Link("Anthropic 定价", destination: ModelPricingCatalog.sources[1])
                    Link("Gemini 定价", destination: ModelPricingCatalog.sources[2])
                    Link("DeepSeek 定价", destination: ModelPricingCatalog.sources[3])
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(accent)
                }
                .accessibilityLabel("设置月度预算")
            }
            Text("\(ModelPricingCatalog.revisionLabel) · 汇率 1 USD = \(usdToCNY, format: .number.precision(.fractionLength(2))) CNY")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(AppUI.textCaption(scheme: scheme))
        }
        .padding(15)
        .softGlassCard(cornerRadius: 20)
    }
}

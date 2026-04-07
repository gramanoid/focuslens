import Charts
import SwiftUI

struct CategoryDonutChart: View {
    let summaries: [CategorySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Category Breakdown")
                .font(.system(.headline, design: .rounded, weight: .bold))

            if #available(macOS 14.0, *) {
                Chart(summaries) { summary in
                    SectorMark(
                        angle: .value("Duration", summary.duration),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(summary.category.color)
                }
                .frame(height: 200)
            } else {
                Chart(summaries) { summary in
                    BarMark(
                        x: .value("Duration", summary.duration / 3600),
                        y: .value("Category", summary.category.title)
                    )
                    .foregroundStyle(summary.category.color)
                }
                .frame(height: 200)
            }

            ForEach(summaries) { summary in
                HStack {
                    Circle()
                        .fill(summary.category.color)
                        .frame(width: 8, height: 8)
                    Text(summary.category.title)
                    Spacer()
                    Text("\(AnalysisAggregator.format(duration: summary.duration)) • \(Int(summary.percentage * 100))%")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Category breakdown chart")
    }
}

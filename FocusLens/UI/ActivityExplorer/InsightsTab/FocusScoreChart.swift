import Charts
import SwiftUI

struct FocusScoreChart: View {
    let points: [FocusScorePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Productivity Score")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(DS.Accent.primary)
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(DS.Accent.primary.opacity(DS.Emphasis.subtle))
            }
            .chartYScale(domain: 0 ... 100)
            .frame(minHeight: 200)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Productivity score over time chart")
    }
}

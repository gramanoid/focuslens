import Charts
import SwiftUI

struct AppUsageChart: View {
    let data: [AppUsageSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("App Usage")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Chart(data) { item in
                BarMark(
                    x: .value("Hours", item.duration / 3600),
                    y: .value("App", item.app)
                )
                .foregroundStyle(item.dominantCategory.color)
            }
            .frame(minHeight: 200)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App usage chart")
    }
}

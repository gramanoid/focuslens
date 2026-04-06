import SwiftUI

struct SummaryCards: View {
    let totalTrackedTime: String
    let mostUsedApp: String
    let longestFocusSession: String
    let contextSwitches: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: DS.Spacing.lg)], spacing: DS.Spacing.lg) {
            SummaryCard(title: "Total Tracked Time", value: totalTrackedTime)
            SummaryCard(title: "Most Used App", value: mostUsedApp)
            SummaryCard(title: "Longest Focus Session", value: longestFocusSession)
            SummaryCard(title: "Context Switches", value: contextSwitches)
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

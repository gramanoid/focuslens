import SwiftUI

struct SummaryCards: View {
    let totalTrackedTime: String
    let mostUsedApp: String
    let longestFocusSession: String
    let contextSwitches: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: DS.Spacing.md)], spacing: DS.Spacing.md) {
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
                .contentTransition(.numericText())
                .motionSafe(.easeOut(duration: DS.Motion.normal), value: value)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

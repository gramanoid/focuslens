import SwiftUI

struct SummaryCards: View {
    let totalTrackedTime: String
    let mostUsedApp: String
    let longestFocusSession: String
    let contextSwitches: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
}

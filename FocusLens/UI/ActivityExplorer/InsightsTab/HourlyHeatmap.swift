import SwiftUI

struct HourlyHeatmap: View {
    let cells: [HourlyHeatCell]
    let onSelect: (Date, Int) -> Void

    var body: some View {
        let days = Dictionary(grouping: cells, by: { Calendar.current.startOfDay(for: $0.day) })
            .map { ($0.key, $0.value.sorted { $0.hour < $1.hour }) }
            .sorted { $0.0 < $1.0 }
        let maxMinutes = max(cells.map(\.minutes).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Hourly Activity Heatmap")
                .font(.system(.headline, design: .rounded, weight: .bold))

            ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(0 ..< 24, id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(days, id: \.0) { day, row in
                    GridRow {
                        Text(day.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(row) { cell in
                            Button {
                                onSelect(day, cell.hour)
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DS.Accent.primary.opacity(0.12 + (cell.minutes / maxMinutes) * 0.88))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)) hour \(cell.hour), \(Int(cell.minutes)) minutes tracked")
                            .help("\(day.formatted(date: .abbreviated, time: .omitted)) \(String(format: "%02d", cell.hour)):00 — \(Int(cell.minutes)) min")
                        }
                    }
                }
            }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

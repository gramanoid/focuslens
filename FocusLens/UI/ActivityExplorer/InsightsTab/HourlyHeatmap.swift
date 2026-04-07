import SwiftUI

struct HourlyHeatmap: View {
    let cells: [HourlyHeatCell]
    let onSelect: (Date, Int) -> Void

    private var days: [(Date, [HourlyHeatCell])] {
        Dictionary(grouping: cells, by: { Calendar.current.startOfDay(for: $0.day) })
            .map { ($0.key, $0.value.sorted { $0.hour < $1.hour }) }
            .sorted { $0.0 < $1.0 }
    }

    private var maxMinutes: Double {
        max(cells.map(\.minutes).max() ?? 0, 1)
    }

    var body: some View {

        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Hourly Activity Heatmap")
                .font(.system(.headline, design: .rounded, weight: .bold))

            ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: DS.Spacing.sm, verticalSpacing: DS.Spacing.sm) {
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
                                RoundedRectangle(cornerRadius: DS.Spacing.xs)
                                    .fill(DS.Accent.primary.opacity(0.12 + (cell.minutes / maxMinutes) * 0.88))
                                    .frame(width: DS.Spacing.xl, height: DS.Spacing.xl)
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

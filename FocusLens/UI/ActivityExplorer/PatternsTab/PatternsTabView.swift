import Charts
import SwiftUI

struct PatternsTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        ScrollView {
            if viewModel.hasEnoughDataForPatterns {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    insightCards
                    weeklyHeatmap
                    HStack(alignment: .top, spacing: DS.Spacing.lg) {
                        dayOfWeekChart
                        optimalSessionCard
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, DS.Spacing.lg)
            } else {
                insufficientDataView
            }
        }
    }

    // MARK: - Insight Cards

    private var insightCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DS.Spacing.md)], spacing: DS.Spacing.md) {
            ForEach(viewModel.cachedPatternInsights) { insight in
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    Image(systemName: insight.icon)
                        .font(.title3)
                        .foregroundStyle(DS.Accent.primary)
                        .frame(width: DS.Spacing.xxl)
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(insight.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text(insight.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
        }
    }

    // MARK: - Weekly Heatmap

    private var weeklyHeatmap: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Weekly Activity Pattern")
                .font(.system(.headline, design: .rounded, weight: .bold))

            let maxMinutes = max(viewModel.cachedWeeklyHeatmap.map(\.averageMinutes).max() ?? 1, 1)

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
                    ForEach(1...7, id: \.self) { weekday in
                        GridRow {
                            Text(Calendar.current.shortWeekdaySymbols[weekday - 1])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: DS.Spacing.xxl + DS.Spacing.sm, alignment: .trailing)
                            ForEach(0 ..< 24, id: \.self) { hour in
                                let cell = viewModel.cachedWeeklyHeatmap.first { $0.dayOfWeek == weekday && $0.hour == hour }
                                let intensity = (cell?.averageMinutes ?? 0) / maxMinutes
                                RoundedRectangle(cornerRadius: DS.Spacing.xs)
                                    .fill(DS.Accent.primary.opacity(0.08 + intensity * 0.82))
                                    .frame(width: DS.Spacing.xl, height: DS.Spacing.xl)
                                    .help("\(Calendar.current.shortWeekdaySymbols[weekday - 1]) \(String(format: "%02d", hour)):00 — \(Int(cell?.averageMinutes ?? 0)) min avg")
                                    .accessibilityLabel("\(Calendar.current.shortWeekdaySymbols[weekday - 1]) \(String(format: "%02d", hour)):00, \(Int(cell?.averageMinutes ?? 0)) minutes average")
                            }
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weekly activity heatmap")
    }

    // MARK: - Day of Week Chart

    private var dayOfWeekChart: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Productivity by Day")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Chart(viewModel.cachedDayOfWeekSummaries) { day in
                BarMark(
                    x: .value("Score", day.averageProductivityScore),
                    y: .value("Day", day.dayName)
                )
                .foregroundStyle(DS.Accent.primary)
            }
            .chartXScale(domain: 0 ... 100)
            .frame(minHeight: 200)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Productivity by day of week chart")
    }

    // MARK: - Optimal Session Card

    private var optimalSessionCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Session Intelligence")
                .font(.system(.headline, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("OPTIMAL FOCUS BLOCK")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    Text(AnalysisAggregator.format(duration: viewModel.cachedOptimalSessionLength))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }

                Text("This is the median length of your deep-work sessions. Schedule focus blocks around this duration for peak effectiveness.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let focusApps = viewModel.cachedAppFocusCorrelation.prefix(5)
                if !focusApps.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("FOCUS APPS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        ForEach(focusApps, id: \.app) { item in
                            HStack {
                                Text(item.app)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("\(Int(item.focusRatio * 100))% deep work")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Insufficient Data

    private var insufficientDataView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Not Enough Data Yet")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Pattern analysis requires at least 7 days of tracked data. Keep FocusLens running and check back soon.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xxl)
    }
}

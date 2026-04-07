import SwiftUI

struct InsightsTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                HStack(alignment: .top) {
                    DateRangeSelectorView(selection: $viewModel.selectedDateRange)
                    Spacer()
                    Menu("Export") {
                        ForEach(ExportFormat.allCases) { format in
                            Button(format.rawValue) {
                                viewModel.triggerExport(format)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                }

                SummaryCards(
                    totalTrackedTime: viewModel.totalTrackedTimeText,
                    mostUsedApp: viewModel.mostUsedAppText,
                    longestFocusSession: viewModel.longestFocusSessionText,
                    contextSwitches: viewModel.contextSwitchesText
                )

                HStack(alignment: .top, spacing: DS.Spacing.lg) {
                    CategoryDonutChart(summaries: viewModel.categorySummaries)
                    HourlyHeatmap(cells: viewModel.hourlyHeatmap) { day, hour in
                        viewModel.jumpTo(day: day, hour: hour)
                    }
                }

                HStack(spacing: DS.Spacing.lg) {
                    AppUsageChart(data: viewModel.appUsage)
                        .frame(maxHeight: .infinity)
                    FocusScoreChart(points: viewModel.focusTrend)
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                ContextSwitchChart(points: viewModel.switchTrend)
            }
            .padding(.bottom, DS.Spacing.lg)
        }
    }
}

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
                .scaleEntrance()

                HStack(alignment: .top, spacing: DS.Spacing.lg) {
                    CategoryDonutChart(summaries: viewModel.categorySummaries)
                        .staggeredEntrance(index: 0, baseDelay: 0.1)
                    HourlyHeatmap(cells: viewModel.hourlyHeatmap) { day, hour in
                        viewModel.jumpTo(day: day, hour: hour)
                    }
                    .staggeredEntrance(index: 1, baseDelay: 0.1)
                }

                HStack(spacing: DS.Spacing.lg) {
                    AppUsageChart(data: viewModel.appUsage)
                        .frame(maxHeight: .infinity)
                        .staggeredEntrance(index: 2, baseDelay: 0.1)
                    FocusScoreChart(points: viewModel.focusTrend)
                        .frame(maxHeight: .infinity)
                        .staggeredEntrance(index: 3, baseDelay: 0.1)
                }
                .fixedSize(horizontal: false, vertical: true)

                ContextSwitchChart(points: viewModel.switchTrend)
                    .staggeredEntrance(index: 4, baseDelay: 0.1)
            }
            .padding(.bottom, DS.Spacing.lg)
        }
    }
}

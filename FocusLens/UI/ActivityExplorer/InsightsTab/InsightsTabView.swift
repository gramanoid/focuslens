import SwiftUI

struct InsightsTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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

                HStack(alignment: .top, spacing: 18) {
                    CategoryDonutChart(summaries: viewModel.categorySummaries)
                    HourlyHeatmap(cells: viewModel.hourlyHeatmap) { day, hour in
                        viewModel.jumpTo(day: day, hour: hour)
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    AppUsageChart(data: viewModel.appUsage)
                    FocusScoreChart(points: viewModel.focusTrend)
                }

                ContextSwitchChart(points: viewModel.switchTrend)
            }
            .padding(.bottom, 20)
        }
    }
}

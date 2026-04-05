import SwiftUI

struct AIAnalysisTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                DateRangeSelectorView(selection: $viewModel.selectedDateRange)

                HStack(alignment: .bottom, spacing: 12) {
                    Picker("Analysis Type", selection: $viewModel.analysisType) {
                        ForEach(AnalysisType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .frame(width: 240)

                    if viewModel.analysisType == .customPrompt {
                        TextField("Ask anything about your tracked data", text: $viewModel.customPrompt)
                    }

                    Button("Generate") {
                        viewModel.generateAnalysis()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }

            StreamingResponseView(text: viewModel.analysisResponse, isStreaming: viewModel.isGeneratingAnalysis)
                .frame(maxHeight: .infinity)

            SavedAnalysesList(analyses: viewModel.analyses, onOpen: viewModel.open(_:), onDelete: viewModel.delete(_:))
                .frame(height: 220)
        }
    }
}

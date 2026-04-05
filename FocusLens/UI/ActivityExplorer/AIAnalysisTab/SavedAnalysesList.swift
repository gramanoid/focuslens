import SwiftUI

struct SavedAnalysesList: View {
    let analyses: [AnalysisRecord]
    let onOpen: (AnalysisRecord) -> Void
    let onDelete: (AnalysisRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Analyses")
                .font(.headline)

            if analyses.isEmpty {
                Text("No saved analyses yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(analyses) { analysis in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(analysis.type.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text(analysis.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Open") {
                                    onOpen(analysis)
                                }
                                Button("Delete", role: .destructive) {
                                    onDelete(analysis)
                                }
                            }
                            .padding(14)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
    }
}

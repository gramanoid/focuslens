import SwiftUI

struct SavedAnalysesList: View {
    let analyses: [AnalysisRecord]
    let onOpen: (AnalysisRecord) -> Void
    let onDelete: (AnalysisRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Saved Analyses")
                .font(.headline)

            if analyses.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.tertiary)
                    Text("Generated analyses are saved here automatically.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.smMd) {
                        ForEach(analyses) { analysis in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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
                            .padding(DS.Spacing.lg)
                            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                        }
                    }
                }
            }
        }
    }
}

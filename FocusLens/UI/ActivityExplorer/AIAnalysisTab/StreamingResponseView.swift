import SwiftUI

struct StreamingResponseView: View {
    let text: String
    let isStreaming: Bool

    private var analysisSections: [AnalysisDisplaySection] {
        AnalysisResponseFormatter.sections(from: text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if isStreaming {
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Streaming from llama.cpp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                renderedText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    @ViewBuilder
    private var renderedText: some View {
        if text.isEmpty {
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: "text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Analysis will load automatically when a local model is connected. You can also choose a type above and generate manually.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.xxl)
        } else if isStreaming {
            // During streaming, render plain text to avoid re-parsing markdown on every token.
            Text(text)
                .textSelection(.enabled)
        } else if !analysisSections.isEmpty {
            AnalysisSectionListView(sections: analysisSections)
                .textSelection(.enabled)
        } else if let attributed = try? AttributedString(markdown: AnalysisResponseFormatter.sanitize(text)) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(AnalysisResponseFormatter.sanitize(text))
                .textSelection(.enabled)
        }
    }
}

private struct AnalysisSectionListView: View {
    let sections: [AnalysisDisplaySection]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(section.title)
                        .font(.headline)

                    ForEach(section.items.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: DS.Spacing.sm) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(section.items[index])
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

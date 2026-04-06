import SwiftUI

struct StreamingResponseView: View {
    let text: String
    let isStreaming: Bool

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
                Text("Pick an analysis type above and hit Generate to get AI insights on your tracked data.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if isStreaming {
            // During streaming, render plain text to avoid re-parsing markdown on every token.
            Text(text)
                .textSelection(.enabled)
        } else if let attributed = try? AttributedString(markdown: text) {
            // Only parse markdown once streaming is complete.
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

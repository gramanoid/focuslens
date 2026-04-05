import SwiftUI

struct StreamingResponseView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isStreaming {
                    HStack(spacing: 8) {
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
            .padding(18)
        }
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var renderedText: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text.isEmpty ? "No analysis generated yet." : text)
                .textSelection(.enabled)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
        }
    }
}

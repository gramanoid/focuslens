import SwiftUI

struct SessionCard: View {
    let block: SessionBlock
    let connectsToPrevious: Bool
    let connectsToNext: Bool

    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(block.category.color)
                    .frame(width: 4, height: connectsToPrevious ? 18 : 6)
                    .opacity(connectsToPrevious ? 1 : 0.35)
                Circle()
                    .fill(block.category.color)
                    .frame(width: 12, height: 12)
                Capsule()
                    .fill(block.category.color)
                    .frame(width: 4, height: connectsToNext ? 44 : 6)
                    .opacity(connectsToNext ? 1 : 0.35)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(block.start.formatted(date: .omitted, time: .shortened)) → \(block.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Image(nsImage: AppIconResolver.icon(for: block.bundleID))
                                .resizable()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(block.app)
                                .font(.headline)
                            Text(block.category.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(block.category.color.opacity(0.2), in: Capsule())
                        }
                    }
                    Spacer()
                    if let image = ImageHelpers.image(from: block.screenshotPath), block.screenshotPath != nil {
                        Button {
                            if let path = block.screenshotPath {
                                QuickLookPreviewController.shared.preview(path: path)
                            }
                        } label: {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(block.task)
                            .font(.body)
                            .lineLimit(expanded ? nil : 1)
                        Spacer()
                        Button {
                            expanded.toggle()
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Confidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(block.confidence * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: block.confidence)
                            .tint(block.category.color)
                    }
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }
}

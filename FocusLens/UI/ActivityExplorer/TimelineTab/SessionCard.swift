import SwiftUI

struct SessionCard: View {
    let block: SessionBlock
    let connectsToPrevious: Bool
    let connectsToNext: Bool

    @State private var expanded = false
    @State private var thumbnailHovered = false

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

            VStack(alignment: .leading, spacing: DS.Spacing.smMd) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(block.start.formatted(date: .omitted, time: .shortened)) → \(block.end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: DS.Spacing.smMd) {
                            Image(nsImage: AppIconResolver.icon(for: block.bundleID))
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(block.app)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text(block.category.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(block.category.color.opacity(DS.Emphasis.medium), in: Capsule())
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
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                                .scaleEffect(thumbnailHovered ? 1.05 : 1.0)
                                .shadow(color: .black.opacity(thumbnailHovered ? 0.3 : 0), radius: 8, y: 4)
                                .animation(.easeOut(duration: DS.Motion.fast), value: thumbnailHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { thumbnailHovered = $0 }
                        .accessibilityLabel("Preview screenshot for \(block.app)")
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(alignment: .top) {
                        Text(block.task)
                            .font(.body)
                            .lineLimit(expanded ? nil : 1)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: DS.Motion.fast)) {
                                expanded.toggle()
                            }
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expanded ? "Collapse details" : "Expand details")
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
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

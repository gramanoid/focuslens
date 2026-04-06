import SwiftUI

/// A reusable dark-surface card used throughout the app for grouping
/// related content with a title and subtitle.
struct SurfaceCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.smMd) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
    }
}

import SwiftUI

struct KeystrokesTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel
    @State private var searchText = ""
    @State private var groupByApp = true

    private var filtered: [KeystrokeRecord] {
        guard !searchText.isEmpty else { return viewModel.rangeKeystrokes }
        let query = searchText.lowercased()
        return viewModel.rangeKeystrokes.filter {
            $0.typedText.lowercased().contains(query) || $0.app.lowercased().contains(query)
        }
    }

    private var grouped: [(String, [KeystrokeRecord])] {
        Dictionary(grouping: filtered, by: \.app)
            .map { ($0.key, $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.1.reduce(0) { $0 + $1.keystrokeCount } > $1.1.reduce(0) { $0 + $1.keystrokeCount } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack {
                DateRangeSelectorView(selection: $viewModel.selectedDateRange)
                Spacer()
                Toggle("Group by app", isOn: $groupByApp)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Group keystrokes by app")
            }

            keystrokeSummary

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search keystrokes", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search keystrokes")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear keystroke search")
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md))

            if filtered.isEmpty {
                emptyState
            } else if groupByApp {
                groupedList
            } else {
                flatList
            }
        }
    }

    private var keystrokeSummary: some View {
        let records = viewModel.rangeKeystrokes
        let totalKeys = records.reduce(0) { $0 + $1.keystrokeCount }
        let uniqueApps = Set(records.map(\.app)).count
        let topApp = Dictionary(grouping: records, by: \.app)
            .max { $0.value.reduce(0) { $0 + $1.keystrokeCount } < $1.value.reduce(0) { $0 + $1.keystrokeCount } }?
            .key ?? "None"

        return HStack(spacing: DS.Spacing.md) {
            KeystrokeStat(title: "TOTAL KEYSTROKES", value: totalKeys.formatted())
            KeystrokeStat(title: "ACTIVE APPS", value: "\(uniqueApps)")
            KeystrokeStat(title: "MOST TYPED IN", value: topApp)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "keyboard")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty
                ? "No keystrokes recorded for this period. Enable keystroke tracking in Preferences."
                : "No keystrokes match your search.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.lg) {
                ForEach(grouped, id: \.0) { app, records in
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack {
                            Image(nsImage: AppIconResolver.icon(for: records.first?.bundleID))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm / 3))
                            Text(app)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Spacer()
                            Text("\(records.reduce(0) { $0 + $1.keystrokeCount }) keys")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        ForEach(records, id: \.id) { record in
                            KeystrokeRow(record: record, showApp: false)
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }
        }
    }

    private var flatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(filtered, id: \.id) { record in
                    KeystrokeRow(record: record, showApp: true)
                        .padding(DS.Spacing.md)
                        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
        }
    }
}

private struct KeystrokeStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

private struct KeystrokeRow: View {
    let record: KeystrokeRecord
    let showApp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                if showApp {
                    Image(nsImage: AppIconResolver.icon(for: record.bundleID))
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm / 4))
                    Text(record.app)
                        .font(.caption.weight(.semibold))
                }
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(record.keystrokeCount) keys")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(record.typedText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .foregroundStyle(.primary.opacity(0.85))
                .accessibilityLabel("Typed in \(record.app): \(String(record.typedText.prefix(80)))")
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

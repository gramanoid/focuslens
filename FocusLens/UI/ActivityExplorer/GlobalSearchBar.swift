import SwiftUI

struct SearchResult: Identifiable {
    let id: String
    let timestamp: Date
    let app: String
    let text: String
    let category: ActivityCategory?
    let source: SearchResultSource

    enum SearchResultSource {
        case session
        case keystroke
    }
}

struct GlobalSearchBar: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel
    @State private var searchText = ""
    @State private var showResults = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search activities, apps, or keystrokes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search all tracked activities")
                    .onSubmit { performSearch() }
                    .onChange(of: searchText) { _ in debouncedSearch() }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        viewModel.globalSearchResults = []
                        showResults = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md))

            if showResults && !viewModel.globalSearchResults.isEmpty {
                SearchResultsDropdown(results: viewModel.globalSearchResults) { result in
                    let day = Calendar.current.startOfDay(for: result.timestamp)
                    let hour = Calendar.current.component(.hour, from: result.timestamp)
                    viewModel.jumpTo(day: day, hour: hour)
                    showResults = false
                    searchText = ""
                }
            }
        }
    }

    private func debouncedSearch() {
        viewModel.debouncedSearchTask?.cancel()
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            viewModel.globalSearchResults = []
            showResults = false
            return
        }
        viewModel.debouncedSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        viewModel.performSearch(query: searchText)
        showResults = !viewModel.globalSearchResults.isEmpty
    }
}

private struct SearchResultsDropdown: View {
    let results: [SearchResult]
    let onSelect: (SearchResult) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(results) { result in
                    Button {
                        onSelect(result)
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: result.source == .session ? "eye.circle" : "keyboard")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.text)
                                    .lineLimit(1)
                                    .font(.system(.body, design: .monospaced))
                                HStack(spacing: DS.Spacing.sm) {
                                    Text(result.app)
                                        .font(.caption.weight(.semibold))
                                    if let cat = result.category {
                                        Text(cat.title)
                                            .font(.caption2)
                                            .padding(.horizontal, DS.Spacing.xs)
                                            .padding(.vertical, 2)
                                            .background(cat.color.opacity(DS.Emphasis.medium), in: Capsule())
                                    }
                                    Spacer()
                                    Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, DS.Spacing.sm)
                        .padding(.horizontal, DS.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverFeedback()
                }
            }
        }
        .frame(maxHeight: 300)
        .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

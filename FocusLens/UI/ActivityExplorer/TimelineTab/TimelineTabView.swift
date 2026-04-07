import SwiftUI

struct TimelineTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        HStack(spacing: DS.Spacing.xl) {
            sidebar
            content
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            DatePicker("Day", selection: $viewModel.selectedDay, displayedComponents: .date)
                .datePickerStyle(.graphical)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Filters")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(ActivityCategory.allCases.filter { $0 != .unknown }) { category in
                            Button {
                                if viewModel.selectedCategories.contains(category) {
                                    viewModel.selectedCategories.remove(category)
                                } else {
                                    viewModel.selectedCategories.insert(category)
                                }
                            } label: {
                                Text(category.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, DS.Spacing.smMd)
                                    .padding(.vertical, DS.Spacing.sm)
                                    .background(
                                        viewModel.selectedCategories.contains(category) ? category.color.opacity(DS.Emphasis.medium) : DS.Surface.card,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(viewModel.selectedCategories.contains(category) ? .isSelected : [])
                            .hoverFeedback()
                        }
                    }
                }

                TextField("Search apps", text: $viewModel.appSearchText)
                Picker("App", selection: $viewModel.selectedApp) {
                    Text("All Apps").tag("")
                    ForEach(viewModel.allApps, id: \.self) { app in
                        Text(app).tag(app)
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Minimum confidence")
                        Spacer()
                        Text("\(Int(viewModel.minimumConfidence * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.minimumConfidence, in: 0 ... 1)
                        .accessibilityLabel("Minimum confidence filter")
                        .accessibilityValue("\(Int(viewModel.minimumConfidence * 100)) percent")
                }

                Toggle("Show only focus sessions", isOn: $viewModel.showOnlyFocusSessions)
            }
            Spacer()
            daySummaryCard
        }
        .frame(width: 300)
        .padding(DS.Spacing.lg)
        .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            HStack {
                Text(viewModel.selectedDay.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Spacer()
                Picker("View", selection: $viewModel.timelineViewMode) {
                    ForEach(TimelineViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            HourScrubber(density: viewModel.hourlyDensityForSelectedDay, selectedHour: $viewModel.selectedHour) { hour in
                viewModel.selectedHour = hour
            }

            if viewModel.timelineViewMode == .cards {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.lg) {
                            ForEach(Array(viewModel.timelineBlocks.enumerated()), id: \.element.id) { index, block in
                                SessionCard(
                                    block: block,
                                    connectsToPrevious: connection(before: index),
                                    connectsToNext: connection(after: index)
                                )
                                .id(block.id)
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedHour) { hour in
                        guard let hour,
                              let block = viewModel.timelineBlocks.first(where: {
                                  Calendar.current.component(.hour, from: $0.start) == hour
                              }) else { return }
                        proxy.scrollTo(block.id, anchor: .top)
                    }
                }
            } else {
                GanttView(blocks: viewModel.timelineBlocks, day: viewModel.selectedDay)
            }
        }
        .padding(DS.Spacing.xl)
        .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    private var daySummaryCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(DS.Accent.primary)
                Text("Day Summary")
                    .font(.caption.weight(.semibold))
            }

            if viewModel.timelineBlocks.isEmpty {
                Text("No sessions recorded for this day yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(daySummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var daySummaryText: String {
        let blocks = viewModel.timelineBlocks
        let totalDuration = blocks.reduce(0.0) { $0 + $1.duration }
        let topApp = Dictionary(grouping: blocks, by: \.app)
            .max(by: { $0.value.reduce(0) { $0 + $1.duration } < $1.value.reduce(0) { $0 + $1.duration } })?
            .key ?? "Unknown"
        let topCategory = Dictionary(grouping: blocks, by: \.category)
            .max(by: { $0.value.count < $1.value.count })?
            .key ?? .other
        let switches = zip(blocks.dropLast(), blocks.dropFirst()).filter { $0.0.app != $0.1.app }.count
        return "\(AnalysisAggregator.format(duration: totalDuration)) tracked across \(blocks.count) sessions. Mostly \(topCategory.title.lowercased()) in \(topApp). \(switches) context switch\(switches == 1 ? "" : "es")."
    }

    private func connection(before index: Int) -> Bool {
        guard index > 0 else { return false }
        return viewModel.timelineBlocks[index - 1].app == viewModel.timelineBlocks[index].app
    }

    private func connection(after index: Int) -> Bool {
        guard index < viewModel.timelineBlocks.count - 1 else { return false }
        return viewModel.timelineBlocks[index + 1].app == viewModel.timelineBlocks[index].app
    }
}

import SwiftUI

struct TimelineTabView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        HStack(spacing: 20) {
            sidebar
            content
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            DatePicker("Day", selection: $viewModel.selectedDay, displayedComponents: .date)
                .datePickerStyle(.graphical)

            VStack(alignment: .leading, spacing: 12) {
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        viewModel.selectedCategories.contains(category) ? category.color.opacity(0.22) : .white.opacity(0.06),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
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

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Minimum confidence")
                        Spacer()
                        Text("\(Int(viewModel.minimumConfidence * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.minimumConfidence, in: 0 ... 1)
                }

                Toggle("Show only focus sessions", isOn: $viewModel.showOnlyFocusSessions)
            }
            Spacer()
        }
        .frame(width: 300)
        .padding(18)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(viewModel.selectedDay.formatted(date: .abbreviated, time: .omitted))
                    .font(.largeTitle.weight(.semibold))
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
                        LazyVStack(spacing: 14) {
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
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(block.id, anchor: .top)
                        }
                    }
                }
            } else {
                GanttView(blocks: viewModel.timelineBlocks, day: viewModel.selectedDay)
            }
        }
        .padding(20)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
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

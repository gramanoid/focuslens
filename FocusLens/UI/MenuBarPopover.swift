import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroSection
                if appState.needsOnboarding {
                    setupSection
                }
                todaySummarySection
                recentEntriesSection
                actionSection
                privacyFootnote
            }
            .padding(20)
        }
        .frame(width: 410, height: 620)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.06),
                    Color(red: 0.02, green: 0.02, blue: 0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(isPresented: $appState.showPreferences) {
            PreferencesView(appState: appState)
                .frame(width: 560, height: 560)
        }
        .sheet(isPresented: $appState.showPermissionSheet) {
            ScreenPermissionSheet(appState: appState)
                .frame(width: 460, height: 320)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(heroAccent.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: appState.statusSymbolName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(heroAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FocusLens")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                            Text(statusTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(heroAccent)
                        }
                    }
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                statusChip(appState.isRunning ? "Running" : "Paused", tone: appState.isRunning ? heroAccent : .secondary)
            }

            HStack(spacing: 10) {
                metricTile(
                    title: "Tracked Today",
                    value: appState.totalTrackedTimeToday > 0 ? AnalysisAggregator.format(duration: appState.totalTrackedTimeToday) : "Waiting",
                    detail: "\(appState.todaySessionCount) captures"
                )
                metricTile(
                    title: "Dominant",
                    value: appState.dominantCategoryToday?.title ?? "None",
                    detail: appState.lastCapturedAt?.formatted(date: .omitted, time: .shortened) ?? "No snapshots yet"
                )
                metricTile(
                    title: "Interval",
                    value: appState.captureInterval.title,
                    detail: "Local-only"
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    heroAccent.opacity(0.14),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    private var setupSection: some View {
        SurfaceCard(title: "Get set up", subtitle: "Three quiet steps to reach your first useful timeline.") {
            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: appState.setupProgress)
                    .tint(heroAccent)

                SetupStepRow(
                    title: "Allow Screen Recording",
                    detail: "FocusLens captures locally on your Mac and never sends screenshots off-device.",
                    state: appState.screenPermissionGranted ? .complete("Allowed") : .action("Open settings"),
                    action: {
                        if appState.screenPermissionGranted {
                            return
                        }
                        appState.showPermissionSheet = true
                    }
                )

                SetupStepRow(
                    title: "Connect your local model",
                    detail: appState.serverReachable ? "Qwen2-VL is reachable on localhost." : "Start llama-server so FocusLens can classify each snapshot.",
                    state: appState.serverReachable ? .complete("Connected") : .action("Copy command"),
                    action: {
                        if !appState.serverReachable {
                            appState.copyServerCommand()
                        }
                    }
                )

                SetupStepRow(
                    title: "Capture the first snapshot",
                    detail: appState.hasCapturedSessions ? "Your timeline is active. Open the dashboard to explore it." : "Take one snapshot now instead of waiting for the next interval.",
                    state: appState.hasCapturedSessions ? .complete("Done") : .action(appState.isReadyForImmediateCapture ? "Capture now" : "Waiting"),
                    action: {
                        if appState.isReadyForImmediateCapture && !appState.hasCapturedSessions {
                            appState.triggerCaptureNow()
                        }
                    }
                )

                if !appState.serverReachable {
                    DisclosureGroup("Server start command", isExpanded: $appState.showServerHelp) {
                        Text(appState.serverStartCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            .padding(.top, 6)
                    }
                    .font(.caption.weight(.medium))
                    .tint(.secondary)
                }
            }
        }
    }

    private var todaySummarySection: some View {
        SurfaceCard(title: "Today", subtitle: appState.hasCapturedSessions ? "A quick read on how your time has been classified so far." : "Once FocusLens captures your first snapshot, this fills in automatically.") {
            if appState.todaySummary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your first snapshot will create the first bar in this summary.")
                        .foregroundStyle(.secondary)
                    if appState.isReadyForImmediateCapture {
                        Button("Capture now") {
                            appState.triggerCaptureNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(heroAccent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Canvas { context, size in
                        let total = max(appState.todaySummary.reduce(0) { $0 + $1.duration }, 1)
                        var x: CGFloat = 0
                        for summary in appState.todaySummary {
                            let width = max(24, size.width * CGFloat(summary.duration / total))
                            let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                            context.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(summary.category.color))
                            x += width + 6
                        }
                    }
                    .frame(height: 22)

                    ForEach(appState.todaySummary) { summary in
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(summary.category.color)
                                    .frame(width: 8, height: 8)
                                Text(summary.category.title)
                            }
                            Spacer()
                            Text(AnalysisAggregator.format(duration: summary.duration))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var recentEntriesSection: some View {
        SurfaceCard(title: "Recent snapshots", subtitle: appState.hasCapturedSessions ? "What FocusLens has seen most recently." : "The latest classifications appear here once tracking begins.") {
            if appState.recentEntries.isEmpty {
                Text("No activity has been captured yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    ForEach(appState.recentEntries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(nsImage: AppIconResolver.icon(for: entry.bundleID))
                                .resizable()
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 7))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.app)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(entry.timestamp, style: .time)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.task)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    capsuleLabel(entry.category.title, tint: entry.category.color)
                                    capsuleLabel("\(Int(entry.confidence * 100))% confidence", tint: .white.opacity(0.18))
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button(appState.hasCapturedSessions ? "Open Dashboard" : "Open Dashboard Anyway") {
                appState.openDashboard()
            }
            .buttonStyle(.borderedProminent)
            .tint(heroAccent)
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button(appState.isRunning ? "Pause Tracking" : "Resume Tracking") {
                    appState.toggleRunning()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Preferences") {
                    appState.showPreferences = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var privacyFootnote: some View {
        HStack {
            Label("100% local", systemImage: "lock.shield")
            Spacer()
            Label(appState.keepScreenshots ? "Keeping screenshots" : "Auto-deleting screenshots", systemImage: appState.keepScreenshots ? "photo.on.rectangle" : "trash")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var heroAccent: Color {
        if !appState.screenPermissionGranted {
            return .orange
        }
        if !appState.serverReachable {
            return .yellow
        }
        if appState.captureStatus == .classifying {
            return .teal
        }
        return .green
    }

    private var statusTitle: String {
        if !appState.screenPermissionGranted {
            return "Needs permission"
        }
        if !appState.serverReachable {
            return "Waiting for local model"
        }
        if !appState.hasCapturedSessions {
            return "Ready for first capture"
        }
        return appState.isRunning ? "Tracking quietly" : "Paused for now"
    }

    private var statusMessage: String {
        if !appState.screenPermissionGranted {
            return "Grant Screen Recording once, and FocusLens can begin building a private timeline of your work."
        }
        if !appState.serverReachable {
            return "Your Mac is ready. Start the local vision server and FocusLens will begin classifying snapshots."
        }
        if !appState.hasCapturedSessions {
            return "Everything is connected. Take the first snapshot now or wait for the next scheduled interval."
        }
        if let lastCapturedAt = appState.lastCapturedAt {
            return "Latest snapshot at \(lastCapturedAt.formatted(date: .omitted, time: .shortened)). Review patterns in the dashboard whenever you want a deeper read."
        }
        return "FocusLens is monitoring in the background and keeping your activity local."
    }

    private func statusChip(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.opacity(0.16), in: Capsule())
    }

    private func metricTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private func capsuleLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
    }
}

private struct ScreenPermissionSheet: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "rectangle.on.rectangle.badge.person.crop")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Screen Recording")
                        .font(.title3.weight(.semibold))
                    Text("FocusLens needs this once so it can understand what is on screen. Everything stays local on your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Snapshots are processed by your local llama.cpp server only.", systemImage: "lock.shield")
                Label("You can choose whether screenshots are kept or deleted after classification.", systemImage: "photo.badge.checkmark")
                Label("You can still open the dashboard and preferences before granting access.", systemImage: "slider.horizontal.3")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Not now") {
                    appState.dismissPermissionSheet()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Open Privacy Settings") {
                    ScreenCapture.openPrivacySettings()
                }
                Button("Check again") {
                    appState.requestScreenPermission()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(24)
        .background(Color(red: 0.04, green: 0.05, blue: 0.06))
    }
}

private struct SurfaceCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct SetupStepRow: View {
    enum State {
        case complete(String)
        case action(String)
    }

    let title: String
    let detail: String
    let state: State
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
    }

    private var iconName: String {
        switch state {
        case .complete:
            return "checkmark"
        case .action:
            return "arrow.right"
        }
    }

    private var accent: Color {
        switch state {
        case .complete:
            return .green
        case .action:
            return .white
        }
    }

    private var buttonTitle: String {
        switch state {
        case .complete(let text), .action(let text):
            return text
        }
    }

    private var isDisabled: Bool {
        if case .action(let text) = state {
            return text == "Waiting"
        }
        return true
    }
}

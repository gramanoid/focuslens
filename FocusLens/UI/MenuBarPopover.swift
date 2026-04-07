import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var appState: AppState
    @ObservedObject var keystrokeMonitor: KeystrokeMonitor

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                heroSection
                dashboardButton
                if appState.needsOnboarding {
                    setupSection
                }
                todaySummarySection
                recentEntriesSection
                secondaryActions
                privacyFootnote
            }
            .padding(DS.Spacing.xl)
        }
        .frame(width: 410, height: 480)
        .background(DS.Background.primary)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(heroAccent.opacity(DS.Emphasis.subtle))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(heroAccent.opacity(isCapturing ? 0.4 : 0), lineWidth: 2)
                                        .frame(width: 40, height: 40)
                                        .scaleEffect(isCapturing ? 1.4 : 1)
                                        .opacity(isCapturing ? 0 : 1)
                                        .animation(
                                            isCapturing ? .easeOut(duration: 1.2).repeatForever(autoreverses: false) : .default,
                                            value: isCapturing
                                        )
                                )
                            if #available(macOS 14.0, *) {
                                Image(systemName: appState.statusSymbolName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(heroAccent)
                                    .contentTransition(.symbolEffect(.replace))
                            } else {
                                Image(systemName: appState.statusSymbolName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(heroAccent)
                            }
                        }
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("FocusLens")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .tracking(-0.5)
                            Text(statusTitle.uppercased())
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .tracking(1.2)
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

            HStack(spacing: DS.Spacing.sm) {
                metricTile(
                    title: "Tracked Today",
                    value: appState.totalTrackedTimeToday > 0 ? AnalysisAggregator.format(duration: appState.totalTrackedTimeToday) : "Waiting",
                    detail: captureCountDetail
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
        .padding(DS.Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    heroAccent.opacity(DS.Emphasis.subtle),
                    DS.Surface.inset
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: DS.Radius.xl)
        )
        .motionSafe(.easeInOut(duration: DS.Motion.normal), value: appState.captureStatus)
        .motionSafe(.easeInOut(duration: DS.Motion.normal), value: appState.serverReachable)
    }

    private var setupSection: some View {
        SurfaceCard(title: "Get set up", subtitle: "Three quiet steps to reach your first useful timeline.") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ProgressView(value: appState.setupProgress)
                    .tint(heroAccent)

                SetupStepRow(
                    title: "Allow Screen Recording",
                    detail: "FocusLens captures locally on your Mac and never sends screenshots off-device.",
                    state: appState.screenPermissionGranted ? .complete("Allowed") : .action("Open settings"),
                    action: {
                        if appState.screenPermissionGranted { return }
                        ScreenCapture.openPrivacySettings()
                    }
                )

                SetupStepRow(
                    title: "Connect your local model",
                    detail: modelSetupDetail,
                    state: modelSetupState,
                    action: {
                        if appState.serverReachable { return }
                        if !appState.serverProcess.isLlamaServerInstalled {
                            appState.openPreferences()
                        } else if appState.selectedModel.isDownloaded {
                            appState.startServer()
                        } else if !appState.downloadManager.status.isDownloading {
                            appState.downloadAndStartModel(appState.selectedModel)
                        }
                    }
                )

                if appState.downloadManager.status.isDownloading {
                    ProgressView(value: appState.downloadManager.overallProgress)
                        .tint(heroAccent)
                }

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
            }
        }
    }

    private var todaySummarySection: some View {
        SurfaceCard(title: "Today", subtitle: appState.hasCapturedSessions ? "A quick read on how your time has been classified so far." : "Once FocusLens captures your first snapshot, this fills in automatically.") {
            if appState.todaySummary.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.smMd) {
                    Text("Your first snapshot will create the first bar in this summary.")
                        .foregroundStyle(.secondary)
                    if appState.isReadyForImmediateCapture {
                        Button("Capture now") {
                            appState.triggerCaptureNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(heroAccent)
                        .hoverFeedback()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.lg)
                .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Canvas { context, size in
                        let count = appState.todaySummary.count
                        let gap: CGFloat = 4
                        let totalGap = gap * CGFloat(max(0, count - 1))
                        let usableWidth = max(0, size.width - totalGap)
                        let totalDuration = max(appState.todaySummary.reduce(0) { $0 + $1.duration }, 1)
                        var x: CGFloat = 0
                        for summary in appState.todaySummary {
                            let fraction = CGFloat(summary.duration / totalDuration)
                            let barWidth = max(4, usableWidth * fraction)
                            let rect = CGRect(x: x, y: 0, width: barWidth, height: size.height)
                            context.fill(Path(roundedRect: rect, cornerRadius: DS.Radius.sm / 2), with: .color(summary.category.color))
                            x += barWidth + gap
                        }
                    }
                    .frame(height: 22)
                    .accessibilityElement()
                    .accessibilityLabel("Today's activity breakdown")

                    ForEach(appState.todaySummary) { summary in
                        HStack {
                            HStack(spacing: DS.Spacing.sm) {
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
                HStack(spacing: DS.Spacing.smMd) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("Snapshots will appear here once tracking begins.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.lg)
                .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(appState.recentEntries) { entry in
                        HStack(alignment: .top, spacing: DS.Spacing.smMd) {
                            Image(nsImage: AppIconResolver.icon(for: entry.bundleID))
                                .resizable()
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm / 2))
                                .accessibilityLabel("\(entry.app) icon")

                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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
                                HStack(spacing: DS.Spacing.sm) {
                                    capsuleLabel(entry.category.title, tint: entry.category.color)
                                    capsuleLabel("\(Int(entry.confidence * 100))% confidence", tint: .white.opacity(DS.Emphasis.medium))
                                }
                            }
                        }
                        .padding(DS.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                }
            }
        }
    }

    private var dashboardButton: some View {
        Button {
            appState.openDashboard()
        } label: {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                Text("Open Dashboard")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(heroAccent)
        .hoverFeedback()
    }

    private var secondaryActions: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.smMd) {
                Button(appState.isRunning ? "Pause Tracking" : "Resume Tracking") {
                    appState.toggleRunning()
                }
                .buttonStyle(.bordered)
                .hoverFeedback()
                .frame(maxWidth: .infinity)

                Button("Preferences") {
                    appState.openPreferences()
                }
                .buttonStyle(.bordered)
                .hoverFeedback()
                .frame(maxWidth: .infinity)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "power")
                    Text("Quit FocusLens")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .hoverFeedback()
            .keyboardShortcut("q")
        }
    }

    private var privacyFootnote: some View {
        HStack {
            Label("100% local", systemImage: "lock.shield")
            Spacer()
            if keystrokeMonitor.isMonitoring {
                Label("Keystrokes", systemImage: "keyboard")
            }
            Label(appState.keepScreenshots ? "Screenshots" : "No screenshots", systemImage: appState.keepScreenshots ? "photo.on.rectangle" : "trash")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Spacing.xs)
    }

    private var captureCountDetail: String {
        let count = appState.todaySessionCount
        if count == 0 { return "No captures yet" }
        if count == 1 { return "1 capture so far" }
        return "\(count) captures"
    }

    private var isCapturing: Bool {
        appState.captureStatus == .capturing || appState.captureStatus == .classifying
    }

    private var heroAccent: Color {
        if !appState.screenPermissionGranted {
            return DS.Accent.warning
        }
        if !appState.serverReachable {
            return DS.Accent.caution
        }
        if appState.captureStatus == .classifying {
            return DS.Accent.processing
        }
        return DS.Accent.primary
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
        if appState.captureStatus == .classifying {
            return "Reading your screen"
        }
        return appState.isRunning ? "Tracking quietly" : "Paused"
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
            let timeAgo = Self.relativeDateFormatter.localizedString(for: lastCapturedAt, relativeTo: .now)
            return "\(timeOfDayGreeting). Last snapshot \(timeAgo)."
        }
        return "\(timeOfDayGreeting). FocusLens is running in the background."
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Burning the midnight oil"
        }
    }

    private var modelSetupDetail: String {
        if appState.serverReachable {
            return "\(appState.selectedModel.displayName) is running on localhost."
        }
        if !appState.serverProcess.isLlamaServerInstalled {
            return "Install llama-server: brew install llama.cpp"
        }
        if appState.downloadManager.status.isDownloading {
            return "Downloading \(appState.selectedModel.displayName)..."
        }
        if appState.selectedModel.isDownloaded {
            return "\(appState.selectedModel.displayName) is ready. Click to start."
        }
        return "Download \(appState.selectedModel.displayName) (\(appState.selectedModel.sizeDescription))."
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        return f
    }()

    private var modelSetupState: SetupStepRow.StepState {
        if appState.serverReachable { return .complete("Connected") }
        if appState.downloadManager.status.isDownloading { return .action("Downloading") }
        if appState.selectedModel.isDownloaded { return .action("Start") }
        if !appState.serverProcess.isLlamaServerInstalled { return .action("Setup") }
        return .action("Download")
    }

    private func statusChip(_ text: String, tone: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if appState.isRunning {
                Circle()
                    .fill(tone)
                    .frame(width: 6, height: 6)
                    .opacity(isCapturing ? 1 : 0.6)
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, DS.Spacing.smMd)
        .padding(.vertical, DS.Spacing.sm)
        .background(tone.opacity(DS.Emphasis.subtle), in: Capsule())
    }

    private func metricTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .help("\(title): \(value) — \(detail)")
    }

    private func capsuleLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(tint, in: Capsule())
    }
}

private struct SetupStepRow: View {
    enum StepState {
        case complete(String)
        case action(String)
    }

    let title: String
    let detail: String
    let state: StepState
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Circle()
                .fill(accent.opacity(DS.Emphasis.medium))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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
            .hoverFeedback()
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
            return DS.Accent.primary
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

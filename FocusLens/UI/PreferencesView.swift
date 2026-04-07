import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updater: AppUpdater
    @ObservedObject var keystrokeMonitor: KeystrokeMonitor
    var onClose: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                headerSection
                trackingSection
                journalSection
                serverSection
                appSection
                updatesSection
                privacySection
            }
            .padding(DS.Spacing.xl)
        }
        .background(DS.Background.primary)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.smMd) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Preferences")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                    Text("Set how quietly FocusLens runs, how it talks to your local model, and how much evidence it keeps.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(DS.Surface.card, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverFeedback()
                    .accessibilityLabel("Close preferences")
                    .keyboardShortcut(.cancelAction)
                }
            }

            HStack(spacing: DS.Spacing.smMd) {
                preferenceStatusChip(
                    title: appState.serverReachable ? "Local model connected" : "Waiting for local model",
                    tint: appState.serverReachable ? DS.Accent.primary : DS.Accent.warning
                )
                preferenceStatusChip(
                    title: keystrokeChipTitle,
                    tint: keystrokeChipTint
                )
                preferenceStatusChip(
                    title: appState.launchAtLogin ? "Starts at login" : "Manual launch",
                    tint: appState.launchAtLogin ? DS.Accent.primary : .secondary
                )
            }
        }
    }

    private var trackingSection: some View {
        SurfaceCard(title: "Tracking", subtitle: "Choose how often FocusLens samples your screen and how much history it keeps.") {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.smMd) {
                    Text("Capture interval")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(CaptureIntervalOption.allCases) { option in
                            Button {
                                appState.updateCaptureInterval(option)
                            } label: {
                                Text(option.title)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DS.Spacing.smMd)
                                    .background(
                                        appState.captureInterval == option ? DS.Accent.primary.opacity(DS.Emphasis.strong) : DS.Surface.card,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    )
                            }
                            .buttonStyle(.plain)
                            .hoverFeedback()
                        }
                    }
                }

                Toggle(isOn: Binding(
                    get: { appState.keystrokeTrackingEnabled },
                    set: { appState.updateKeystrokeTracking($0) }
                )) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Keystroke tracking")
                        Text("Records what you type to enrich AI classification. Requires Accessibility permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.keystrokeTrackingEnabled && !appState.accessibilityPermissionGranted {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Accent.warning)
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text("Accessibility permission required")
                                    .font(.subheadline.weight(.medium))
                                Text("Enable FocusLens in System Settings → Privacy & Security → Accessibility, then click Check Again below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: DS.Spacing.sm) {
                            Button("Open Settings") {
                                KeystrokeMonitor.openAccessibilitySettings()
                                // Re-focus Preferences after a delay so it doesn't stay behind System Settings
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    PreferencesWindowController.shared.window?.makeKeyAndOrderFront(nil)
                                    NSApp.activate(ignoringOtherApps: true)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DS.Accent.warning)
                            Button("Check Again") {
                                appState.refreshPermissionState()
                                if appState.accessibilityPermissionGranted {
                                    appState.updateKeystrokeTracking(true)
                                }
                                // Re-focus in case window lost focus
                                PreferencesWindowController.shared.window?.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                            .buttonStyle(.bordered)
                            .hoverFeedback()
                        }
                        Text("If already enabled, quit and relaunch FocusLens — macOS requires a restart to activate Accessibility permissions.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Accent.warning.opacity(DS.Emphasis.subtle), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                Toggle(isOn: Binding(
                    get: { appState.keepScreenshots },
                    set: { appState.updateKeepScreenshots($0) }
                )) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Keep screenshots")
                        Text("Disable this if you only want classifications and not the original images.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.keepScreenshots {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("Screenshot folder")
                            .font(.subheadline.weight(.medium))
                        HStack {
                            TextField("Default (Application Support)", text: Binding(
                                get: { appState.screenshotDirectoryPath },
                                set: { appState.updateScreenshotDirectory($0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    appState.updateScreenshotDirectory(url.path)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("Screenshots are saved as YYYY-MM-DD_HH-mm-ss_AppName.png")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("Auto-delete after")
                            .font(.subheadline.weight(.medium))
                        Picker("", selection: Binding(
                            get: { appState.screenshotRetentionDays },
                            set: { appState.updateScreenshotRetention($0) }
                        )) {
                            Text("1 day").tag(1)
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                            Text("Never").tag(0)
                        }
                        .pickerStyle(.segmented)
                        Text("At 30s intervals, screenshots use ~2.6 GB/day. Older screenshots are deleted on launch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.smMd) {
                    HStack {
                        Text("Idle detection")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if appState.isUserIdle {
                            Text("Currently idle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DS.Accent.caution)
                        }
                    }
                    Picker("", selection: Binding(
                        get: { appState.idleThresholdMinutes },
                        set: { appState.updateIdleThreshold($0) }
                    )) {
                        Text("Off").tag(0)
                        Text("1 min").tag(1)
                        Text("2 min").tag(2)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                    }
                    .pickerStyle(.segmented)
                    Text("Pauses capture when no keyboard or mouse activity is detected. Prevents duplicate screenshots when caffeine apps keep the screen on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Excluded apps")
                        .font(.subheadline.weight(.medium))
                    TextField("com.1password.1password, com.apple.KeychainAccess", text: Binding(
                        get: { appState.excludedAppsText },
                        set: { appState.updateExcludedApps($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("Use comma-separated bundle IDs for apps FocusLens should ignore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var journalSection: some View {
        SurfaceCard(title: "Work Journal", subtitle: "Auto-generate a daily markdown journal summarizing your work.") {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Toggle(isOn: Binding(
                    get: { appState.autoJournalEnabled },
                    set: { appState.updateAutoJournal($0) }
                )) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Generate journal on quit")
                        Text("Creates a markdown file when FocusLens exits, summarizing the day's activity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Journal folder")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        TextField("~/Documents/FocusLens/journals", text: Binding(
                            get: { appState.journalDirectoryPath },
                            set: { appState.updateJournalDirectory($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url {
                                appState.updateJournalDirectory(url.path)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Journals are saved as YYYY-MM-DD.md with YAML frontmatter for easy indexing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var serverSection: some View {
        SurfaceCard(title: "Local model", subtitle: "Select a vision model. FocusLens downloads it and starts the server automatically.") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if !appState.serverProcess.isLlamaServerInstalled {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.Accent.warning)
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("llama-server not found")
                                .font(.subheadline.weight(.medium))
                            Text("Install with: brew install llama.cpp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Accent.warning.opacity(DS.Emphasis.subtle), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                Picker("Model", selection: Binding(
                    get: { appState.selectedModel },
                    set: { appState.selectModel($0) }
                )) {
                    ForEach(ModelDefinition.recommended) { model in
                        HStack {
                            Text(model.displayName)
                            Text("(\(model.sizeDescription))")
                                .foregroundStyle(.secondary)
                            if model.isDownloaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DS.Accent.primary)
                            }
                        }
                        .tag(model)
                    }
                    Text("Custom...").tag(ModelDefinition.custom)
                }

                selectedModelInfoPanel

                if appState.selectedModel.id == "custom" {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        TextField("Model file path (.gguf)", text: Binding(
                            get: { appState.customModelPath },
                            set: { appState.updateCustomModelPath($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        TextField("mmproj file path (.gguf)", text: Binding(
                            get: { appState.customMmprojPath },
                            set: { appState.updateCustomMmprojPath($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }

                modelStatusRow
                modelActionButtons

                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        TextField("http://localhost:8080", text: Binding(
                            get: { appState.serverBaseURLString },
                            set: { appState.updateServerURL($0) }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Text(appState.serverStartCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(DS.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    }
                    .padding(.top, DS.Spacing.sm)
                }
                .font(.caption.weight(.medium))
                .tint(.secondary)
            }
        }
    }

    private var selectedModelInfoPanel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(appState.selectedModel.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Label("Pros", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Accent.primary)
                    ForEach(appState.selectedModel.pros, id: \.self) { pro in
                        Text(pro)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Label("Cons", systemImage: "minus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Accent.warning)
                    ForEach(appState.selectedModel.cons, id: \.self) { con in
                        Text(con)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var modelStatusRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle()
                .fill(serverStatusColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(serverStatusText)
                .font(.subheadline.weight(.medium))
                .accessibilityLabel("Server status: \(serverStatusText)")
            Spacer()
            if case .downloading(_, let progress) = appState.downloadManager.status {
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelActionButtons: some View {
        HStack(spacing: DS.Spacing.sm) {
            if appState.downloadManager.status.isDownloading {
                ProgressView(value: appState.downloadManager.overallProgress)
                    .tint(DS.Accent.primary)
                    .accessibilityLabel("Download progress: \(Int(appState.downloadManager.overallProgress * 100))%")
                Button("Cancel") {
                    appState.downloadManager.cancel()
                }
                .buttonStyle(.bordered)
            } else if appState.selectedModel.id != "custom" && !appState.selectedModel.isDownloaded {
                Button("Download \(appState.selectedModel.displayName)") {
                    appState.downloadAndStartModel(appState.selectedModel)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Accent.primary)
            } else if appState.serverReachable {
                // Server is reachable — show Stop only if we manage the process
                if appState.serverProcess.status.isActive {
                    Button("Stop Server") {
                        appState.stopServer()
                    }
                    .buttonStyle(.bordered)
                }
                // If server is reachable but externally managed, show nothing
            } else if appState.serverProcess.status.isActive {
                Button("Stop Server") {
                    appState.stopServer()
                }
                .buttonStyle(.bordered)
            } else if appState.selectedModel.isDownloaded || appState.selectedModel.id == "custom" {
                Button("Start Server") {
                    appState.startServer()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Accent.primary)
            }

            if case .failed(let message) = appState.downloadManager.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DS.Accent.warning)
                    .lineLimit(2)
            }

            if case .failed(let message) = appState.serverProcess.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DS.Accent.warning)
                    .lineLimit(2)
            }
        }
    }

    private var serverStatusColor: Color {
        if appState.serverReachable { return DS.Accent.primary }
        switch appState.serverProcess.status {
        case .starting: return DS.Accent.caution
        case .running: return DS.Accent.primary
        case .failed: return .red
        case .stopped: return DS.Accent.warning
        }
    }

    private var serverStatusText: String {
        if appState.serverReachable { return "Server connected" }
        if appState.downloadManager.status.isDownloading { return "Downloading model..." }
        switch appState.serverProcess.status {
        case .starting: return "Server starting..."
        case .running: return "Server running, waiting for health check..."
        case .failed: return "Server error"
        case .stopped:
            if appState.selectedModel.isDownloaded || appState.selectedModel.id == "custom" {
                return "Server stopped"
            }
            return "Model not downloaded"
        }
    }

    private var appSection: some View {
        SurfaceCard(title: "App Behavior", subtitle: "Keep FocusLens running quietly in the background.") {
            Toggle(isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.updateLaunchAtLogin($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Start FocusLens automatically so your timeline begins without a manual step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var updatesSection: some View {
        SurfaceCard(title: "Updates", subtitle: "Check for new versions from GitHub Releases.") {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Text("Current version")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(updater.currentVersion)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                switch updater.status {
                case .idle:
                    Button("Check for Updates") {
                        Task { await updater.checkForUpdates() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Accent.primary)
                    .hoverFeedback()

                case .checking:
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .upToDate:
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Accent.primary)
                        Text("You're on the latest version.")
                            .font(.subheadline)
                    }
                    Button("Check Again") {
                        Task { await updater.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .hoverFeedback()

                case .available(let version, let notes, let url):
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(DS.Accent.primary)
                            Text("Version \(version) available")
                                .font(.subheadline.weight(.semibold))
                        }
                        if !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.Spacing.md)
                                .background(DS.Surface.inset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                        }
                        Button("Download & Install") {
                            Task { await updater.downloadAndInstall(url: url) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DS.Accent.primary)
                        .hoverFeedback()
                    }

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack {
                            Text("Downloading...")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress)
                            .tint(DS.Accent.primary)
                    }

                case .installing:
                    HStack(spacing: DS.Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing... FocusLens will restart.")
                            .font(.subheadline)
                    }

                case .failed(let message):
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Accent.warning)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: DS.Spacing.sm) {
                            if updater.lastDownloadedDMG != nil {
                                Button("Retry Install") {
                                    Task { await updater.retryInstall() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(DS.Accent.primary)
                                .hoverFeedback()
                            }
                            Button("Check Again") {
                                Task { await updater.checkForUpdates() }
                            }
                            .buttonStyle(.bordered)
                            .hoverFeedback()
                        }
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        SurfaceCard(title: "Privacy", subtitle: "Designed to feel safe because it is safe.") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("All inference stays on your Mac.", systemImage: "lock.shield")
                Label("No cloud APIs. No telemetry.", systemImage: "wifi.slash")
                Label("Screenshots are optional and stored in Application Support.", systemImage: "internaldrive")
                Label("Keystrokes are stored locally and never leave your Mac.", systemImage: "keyboard")
                Label("Password fields are automatically skipped.", systemImage: "lock.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var keystrokeChipTitle: String {
        if keystrokeMonitor.isMonitoring { return "Keystrokes active" }
        if appState.keystrokeTrackingEnabled && !appState.accessibilityPermissionGranted { return "Keystrokes need permission" }
        if !appState.keystrokeTrackingEnabled { return "Keystrokes disabled" }
        return "Keystrokes off"
    }

    private var keystrokeChipTint: Color {
        if keystrokeMonitor.isMonitoring { return DS.Accent.primary }
        if appState.keystrokeTrackingEnabled && !appState.accessibilityPermissionGranted { return DS.Accent.warning }
        return .secondary
    }

    private func preferenceStatusChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, DS.Spacing.smMd)
            .padding(.vertical, DS.Spacing.sm)
            .background(tint.opacity(DS.Emphasis.subtle), in: Capsule())
    }
}


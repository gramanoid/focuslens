import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                trackingSection
                serverSection
                appSection
                privacySection
            }
            .padding(22)
        }
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
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preferences")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Set how quietly FocusLens runs, how it talks to your local model, and how much evidence it keeps.")
                .foregroundStyle(.secondary)
        }
    }

    private var trackingSection: some View {
        PreferenceCard(title: "Tracking", subtitle: "Choose how often FocusLens samples your screen and how much history it keeps.") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Capture interval")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        ForEach(CaptureIntervalOption.allCases) { option in
                            Button {
                                appState.updateCaptureInterval(option)
                            } label: {
                                Text(option.title)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        appState.captureInterval == option ? Color.green.opacity(0.24) : Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Toggle(isOn: Binding(
                    get: { appState.keepScreenshots },
                    set: { appState.updateKeepScreenshots($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep screenshots")
                        Text("Disable this if you only want classifications and not the original images.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
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

    private var serverSection: some View {
        PreferenceCard(title: "Local model", subtitle: "FocusLens only talks to a localhost OpenAI-compatible server.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Circle()
                        .fill(appState.serverReachable ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(appState.serverReachable ? "Server connected" : "Server unavailable")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Copy start command") {
                        appState.copyServerCommand()
                    }
                    .buttonStyle(.bordered)
                }

                TextField("http://localhost:8080", text: Binding(
                    get: { appState.serverBaseURLString },
                    set: { appState.updateServerURL($0) }
                ))
                .textFieldStyle(.roundedBorder)

                Text(appState.serverStartCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var appSection: some View {
        PreferenceCard(title: "App behavior", subtitle: "Keep FocusLens close at hand without demanding attention.") {
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

    private var privacySection: some View {
        PreferenceCard(title: "Privacy", subtitle: "Designed to feel safe because it is safe.") {
            VStack(alignment: .leading, spacing: 8) {
                Label("All inference stays on your Mac.", systemImage: "lock.shield")
                Label("No cloud APIs. No telemetry.", systemImage: "wifi.slash")
                Label("Screenshots are optional and stored in Application Support.", systemImage: "internaldrive")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct PreferenceCard<Content: View>: View {
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }
}

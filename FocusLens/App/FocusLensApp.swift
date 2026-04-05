import AppKit
import SwiftUI

final class FocusLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct FocusLensApp: App {
    @NSApplicationDelegateAdaptor(FocusLensAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--self-check") {
            do {
                try SelfCheck.run()
                FileHandle.standardOutput.write(Data("FocusLens checks passed.\n".utf8))
                exit(0)
            } catch {
                let message = error.localizedDescription + "\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(appState: appState)
                .environmentObject(appState)
        } label: {
            StatusMenuBarLabel(status: appState.captureStatus, serverReachable: appState.serverReachable)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(appState: appState)
                .frame(width: 520, height: 360)
        }
    }
}

struct StatusMenuBarLabel: View {
    let status: AppState.CaptureStatus
    let serverReachable: Bool

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
    }

    private var symbolName: String {
        switch status {
        case .idle:
            return serverReachable ? "scope" : "exclamationmark.triangle.fill"
        case .capturing:
            return "camera.circle.fill"
        case .classifying:
            return "brain.head.profile"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .idle:
            return serverReachable ? Color.green : Color.orange
        case .capturing:
            return Color.cyan
        case .classifying:
            return Color.teal
        case .warning:
            return Color.orange
        }
    }
}

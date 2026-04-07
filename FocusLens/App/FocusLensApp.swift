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
            MenuBarPopover(appState: appState, keystrokeMonitor: appState.keystrokeMonitor)
                .environmentObject(appState)
        } label: {
            StatusMenuBarLabel(status: appState.captureStatus, serverReachable: appState.serverReachable, isUserIdle: appState.isUserIdle)
        }
        .menuBarExtraStyle(.window)
    }
}

struct StatusMenuBarLabel: View {
    let status: AppState.CaptureStatus
    let serverReachable: Bool
    var isUserIdle = false

    var body: some View {
        Image(systemName: symbolName)
    }

    /// Menu bar icons are template images — macOS ignores color.
    /// State is communicated purely through symbol shape.
    private var symbolName: String {
        if isUserIdle { return "pause.circle" }
        switch status {
        case .idle:
            return serverReachable ? "scope" : "exclamationmark.triangle"
        case .capturing:
            return "camera.circle.fill"
        case .classifying:
            return "brain.head.profile.fill"
        case .warning:
            return "exclamationmark.triangle"
        }
    }
}

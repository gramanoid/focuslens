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
    }
}

struct StatusMenuBarLabel: View {
    let status: AppState.CaptureStatus
    let serverReachable: Bool

    var body: some View {
        let image = Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
        if #available(macOS 14.0, *) {
            image.contentTransition(.symbolEffect(.replace))
        } else {
            image
        }
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
            return serverReachable ? DS.Accent.primary : DS.Accent.warning
        case .capturing:
            return Color.cyan
        case .classifying:
            return DS.Accent.processing
        case .warning:
            return DS.Accent.warning
        }
    }
}

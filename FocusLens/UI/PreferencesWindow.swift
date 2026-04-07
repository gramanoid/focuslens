import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func show(appState: AppState) {
        if window == nil {
            let rootView = PreferencesView(appState: appState, updater: appState.updater, keystrokeMonitor: appState.keystrokeMonitor) { [weak self] in
                self?.window?.performClose(nil)
            }
            let hostingController = NSHostingController(rootView: AnyView(rootView))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "FocusLens Preferences"
            window.setContentSize(NSSize(width: 620, height: 560))
            window.minSize = NSSize(width: 540, height: 460)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.center()
            self.window = window
        } else if let hostingController = window?.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = AnyView(
                PreferencesView(appState: appState, updater: appState.updater, keystrokeMonitor: appState.keystrokeMonitor) { [weak self] in
                    self?.window?.performClose(nil)
                }
            )
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

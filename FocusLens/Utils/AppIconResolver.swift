import AppKit
import Foundation

enum AppIconResolver {
    static func icon(for bundleID: String?) -> NSImage {
        guard let bundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

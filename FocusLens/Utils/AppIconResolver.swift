import AppKit
import Foundation

enum AppIconResolver {
    static func displayName(for bundleID: String?, fallback: String) -> String {
        guard let bundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return fallback
        }

        let bundle = Bundle(url: appURL)
        let appName = (
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            FileManager.default.displayName(atPath: appURL.path)
        )
        .replacingOccurrences(of: ".app", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return appName.isEmpty ? fallback : appName
    }

    static func icon(for bundleID: String?) -> NSImage {
        guard let bundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

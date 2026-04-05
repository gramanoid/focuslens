import AppKit
import Foundation

struct ScreenCapturePayload {
    let timestamp: Date
    let activeAppName: String
    let activeBundleID: String?
    let screenshotURL: URL
    let resizedPNGData: Data
}

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case captureFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is required for FocusLens."
        case .captureFailed:
            "FocusLens could not capture the current screen."
        case .encodingFailed:
            "FocusLens could not encode the screenshot."
        }
    }
}

enum ScreenCapture {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        guard !hasPermission() else { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func capture() throws -> ScreenCapturePayload {
        guard hasPermission() else {
            throw ScreenCaptureError.permissionDenied
        }

        let timestamp = Date()
        guard let image = CGWindowListCreateImage(
            .infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureError.captureFailed
        }

        guard
            let fullPNGData = ImageHelpers.pngData(from: image),
            let resizedPNGData = ImageHelpers.resizedPNGData(from: image)
        else {
            throw ScreenCaptureError.encodingFailed
        }

        let screenshotsDirectory = try ImageHelpers.screenshotsDirectory()
        let unixTimestamp = Int64((timestamp.timeIntervalSince1970 * 1000).rounded())
        let fileURL = screenshotsDirectory.appendingPathComponent("\(unixTimestamp).png")
        try ImageHelpers.write(fullPNGData, to: fileURL)

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        return ScreenCapturePayload(
            timestamp: timestamp,
            activeAppName: frontmostApplication?.localizedName ?? "Unknown App",
            activeBundleID: frontmostApplication?.bundleIdentifier,
            screenshotURL: fileURL,
            resizedPNGData: resizedPNGData
        )
    }
}

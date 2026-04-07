import AppKit
import Foundation

struct ScreenCapturePayload {
    let timestamp: Date
    let activeAppName: String
    let activeBundleID: String?
    let screenshotURL: URL
    let resizedPNGData: Data
    let isBlankCapture: Bool
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

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func capture(screenshotDirectory: String? = nil) throws -> ScreenCapturePayload {
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

        let screenshotsDirectory = try ImageHelpers.screenshotsDirectory(customPath: screenshotDirectory)
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let appSlug = (frontmostApplication?.localizedName ?? "Unknown")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileURL = screenshotsDirectory.appendingPathComponent("\(dateFormatter.string(from: timestamp))_\(appSlug).png")
        try ImageHelpers.write(fullPNGData, to: fileURL)

        let isBlank = ImageHelpers.isBlankCapture(image)
        return ScreenCapturePayload(
            timestamp: timestamp,
            activeAppName: frontmostApplication?.localizedName ?? "Unknown App",
            activeBundleID: frontmostApplication?.bundleIdentifier,
            screenshotURL: fileURL,
            resizedPNGData: resizedPNGData,
            isBlankCapture: isBlank
        )
    }
}

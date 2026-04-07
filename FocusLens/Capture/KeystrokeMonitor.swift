import AppKit
import ApplicationServices
import Foundation

struct KeystrokeSegment {
    let app: String
    let bundleID: String?
    let text: String
    let keystrokeCount: Int
    let startTime: Date
    let endTime: Date
}

@MainActor
final class KeystrokeMonitor: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var totalKeystrokesSinceFlush = 0

    private var monitor: Any?
    private var segments: [MutableSegment] = []
    private var excludedBundleIDs: Set<String> = []

    fileprivate static let maxTextLength = 2000

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func start(excludedBundleIDs: Set<String>) {
        stop()
        guard Self.hasAccessibilityPermission() else { return }

        self.excludedBundleIDs = excludedBundleIDs
        segments = []
        totalKeystrokesSinceFlush = 0

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
        }
        isMonitoring = true
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isMonitoring = false
    }

    func updateExcludedApps(_ ids: Set<String>) {
        excludedBundleIDs = ids
    }

    /// Returns all buffered segments and resets the buffer.
    func flush() -> [KeystrokeSegment] {
        let flushed = segments.map { $0.freeze() }
        segments = []
        totalKeystrokesSinceFlush = 0
        return flushed
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Secure input fields (password fields) return nil characters
        guard let characters = event.characters, !characters.isEmpty else { return }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier
        let appName = frontmostApp?.localizedName ?? "Unknown"

        // Respect excluded apps
        if let bundleID, excludedBundleIDs.contains(bundleID) { return }

        let now = Date()
        totalKeystrokesSinceFlush += 1

        // Append to current segment if same app, otherwise start new segment
        if let last = segments.last, last.bundleID == bundleID {
            last.append(characters, at: now)
        } else {
            let segment = MutableSegment(
                app: AppIconResolver.displayName(for: bundleID, fallback: appName),
                bundleID: bundleID,
                startTime: now
            )
            segment.append(characters, at: now)
            segments.append(segment)
        }
    }
}

private final class MutableSegment {
    let app: String
    let bundleID: String?
    let startTime: Date
    private(set) var endTime: Date
    private var textBuffer: String = ""
    private(set) var keystrokeCount: Int = 0

    init(app: String, bundleID: String?, startTime: Date) {
        self.app = app
        self.bundleID = bundleID
        self.startTime = startTime
        self.endTime = startTime
    }

    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet.letters
        set.formUnion(.decimalDigits)
        set.formUnion(.punctuationCharacters)
        set.formUnion(.symbols)
        set.formUnion(.whitespaces)
        set.insert(charactersIn: "\n\r\t")
        return set
    }()

    func append(_ characters: String, at time: Date) {
        keystrokeCount += 1
        endTime = time

        // Handle backspace/delete: remove last character instead of appending
        if characters == "\u{7F}" || characters == "\u{8}" {
            if !textBuffer.isEmpty {
                textBuffer.removeLast()
            }
            return
        }

        // Only record letters, numbers, punctuation, symbols, and whitespace.
        // This filters out arrow keys, function keys, escape, and other control characters.
        let filtered = characters.unicodeScalars.filter { Self.allowedCharacters.contains($0) }
        guard !filtered.isEmpty else { return }
        let clean = String(String.UnicodeScalarView(filtered))

        if textBuffer.count < KeystrokeMonitor.maxTextLength {
            textBuffer.append(clean)
        }
    }

    func freeze() -> KeystrokeSegment {
        KeystrokeSegment(
            app: app,
            bundleID: bundleID,
            text: textBuffer,
            keystrokeCount: keystrokeCount,
            startTime: startTime,
            endTime: endTime
        )
    }
}

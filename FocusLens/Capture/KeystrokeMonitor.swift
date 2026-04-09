import AppKit
import ApplicationServices
import Foundation

private enum KeystrokeMonitorConstants {
    static let maxTextLength = 2000
    static let segmentGapThreshold: TimeInterval = 12
    static let mergeGapThreshold: TimeInterval = 2
    static let minimumTextLength = 2
    static let minimumKeystrokeCount = 2
}

struct KeystrokeSegment {
    let app: String
    let bundleID: String?
    let text: String
    let keystrokeCount: Int
    let startTime: Date
    let endTime: Date

    var duration: TimeInterval {
        max(0, endTime.timeIntervalSince(startTime))
    }
}

enum KeystrokeSegmentProcessor {
    private static let repeatedSpacesRegex = try! NSRegularExpression(pattern: #"[ ]{2,}"#)
    private static let repeatedBlankLinesRegex = try! NSRegularExpression(pattern: #"\n{3,}"#)

    static func shouldAppend(
        to segment: KeystrokeSegment,
        app: String,
        bundleID: String?,
        at time: Date
    ) -> Bool {
        guard time.timeIntervalSince(segment.endTime) <= KeystrokeMonitorConstants.segmentGapThreshold else {
            return false
        }

        if let existingBundleID = segment.bundleID, let bundleID {
            return existingBundleID == bundleID
        }

        return segment.bundleID == nil && bundleID == nil && segment.app == app
    }

    static func finalize(_ segments: [KeystrokeSegment]) -> [KeystrokeSegment] {
        let normalized = segments.compactMap(normalize(segment:))
        guard var current = normalized.first else { return [] }

        var merged: [KeystrokeSegment] = []
        for segment in normalized.dropFirst() {
            if canMerge(current, segment) {
                current = KeystrokeSegment(
                    app: current.app,
                    bundleID: current.bundleID ?? segment.bundleID,
                    text: mergeText(current.text, segment.text),
                    keystrokeCount: current.keystrokeCount + segment.keystrokeCount,
                    startTime: current.startTime,
                    endTime: segment.endTime
                )
            } else {
                merged.append(current)
                current = segment
            }
        }

        merged.append(current)
        return merged
    }

    private static func normalize(segment: KeystrokeSegment) -> KeystrokeSegment? {
        let cleanedText = normalizeText(segment.text)
        guard !cleanedText.isEmpty else { return nil }
        guard cleanedText.count >= KeystrokeMonitorConstants.minimumTextLength || segment.keystrokeCount >= KeystrokeMonitorConstants.minimumKeystrokeCount else {
            return nil
        }

        return KeystrokeSegment(
            app: segment.app,
            bundleID: segment.bundleID,
            text: cleanedText,
            keystrokeCount: segment.keystrokeCount,
            startTime: segment.startTime,
            endTime: segment.endTime
        )
    }

    private static func normalizeText(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        let allowedScalars = normalizedNewlines.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar)
        }
        var result = String(String.UnicodeScalarView(allowedScalars))

        let repeatedSpaceRange = NSRange(location: 0, length: (result as NSString).length)
        result = repeatedSpacesRegex.stringByReplacingMatches(in: result, range: repeatedSpaceRange, withTemplate: " ")

        let lines = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        result = lines.joined(separator: "\n")

        let repeatedBlankLineRange = NSRange(location: 0, length: (result as NSString).length)
        result = repeatedBlankLinesRegex.stringByReplacingMatches(in: result, range: repeatedBlankLineRange, withTemplate: "\n\n")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canMerge(_ lhs: KeystrokeSegment, _ rhs: KeystrokeSegment) -> Bool {
        guard rhs.startTime.timeIntervalSince(lhs.endTime) <= KeystrokeMonitorConstants.mergeGapThreshold else {
            return false
        }

        if let lhsBundleID = lhs.bundleID, let rhsBundleID = rhs.bundleID {
            return lhsBundleID == rhsBundleID
        }

        return lhs.bundleID == nil && rhs.bundleID == nil && lhs.app == rhs.app
    }

    private static func mergeText(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }

        let lhsLast = lhs.last
        let rhsFirst = rhs.first
        let shouldInsertSpace =
            lhsLast?.isWhitespace == false &&
            rhsFirst?.isWhitespace == false &&
            rhsFirst?.isPunctuation == false

        return shouldInsertSpace ? "\(lhs) \(rhs)" : lhs + rhs
    }
}

@MainActor
final class KeystrokeMonitor: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var totalKeystrokesSinceFlush = 0

    private var monitor: Any?
    private var segments: [MutableSegment] = []
    private var excludedBundleIDs: Set<String> = []

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
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
        let flushed = KeystrokeSegmentProcessor.finalize(segments.map { $0.freeze() })
        segments = []
        totalKeystrokesSinceFlush = 0
        return flushed
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.function) {
            return
        }

        // Secure input fields (password fields) return nil characters
        guard let characters = event.characters, !characters.isEmpty else { return }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier
        let appName = frontmostApp?.localizedName ?? "Unknown"
        let resolvedApp = AppIconResolver.displayName(for: bundleID, fallback: appName)

        // Respect excluded apps
        if let bundleID, excludedBundleIDs.contains(bundleID) { return }

        let now = Date()

        // Append to current segment if same app, otherwise start new segment
        if let last = segments.last, KeystrokeSegmentProcessor.shouldAppend(to: last.freeze(), app: resolvedApp, bundleID: bundleID, at: now) {
            if last.append(characters, at: now) {
                totalKeystrokesSinceFlush += 1
            }
        } else {
            let segment = MutableSegment(
                app: resolvedApp,
                bundleID: bundleID,
                startTime: now
            )
            if segment.append(characters, at: now) {
                segments.append(segment)
                totalKeystrokesSinceFlush += 1
            }
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

    @discardableResult
    func append(_ characters: String, at time: Date) -> Bool {
        // Handle backspace/delete: remove last character instead of appending
        if characters == "\u{7F}" || characters == "\u{8}" {
            keystrokeCount += 1
            endTime = time
            if !textBuffer.isEmpty {
                textBuffer.removeLast()
            }
            return true
        }

        // Only record letters, numbers, punctuation, symbols, and whitespace.
        // This filters out arrow keys, function keys, escape, and other control characters.
        let filtered = characters.unicodeScalars.filter { Self.allowedCharacters.contains($0) }
        guard !filtered.isEmpty else { return false }
        let clean = String(String.UnicodeScalarView(filtered))

        keystrokeCount += 1
        endTime = time
        if textBuffer.count < KeystrokeMonitorConstants.maxTextLength {
            textBuffer.append(clean)
        }
        return true
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

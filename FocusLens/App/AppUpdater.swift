import AppKit
import Foundation

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, notes: String, downloadURL: URL)
    case downloading(progress: Double)
    case installing
    case failed(String)

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate), (.installing, .installing):
            return true
        case let (.available(v1, _, _), .available(v2, _, _)):
            return v1 == v2
        case let (.downloading(p1), .downloading(p2)):
            return p1 == p2
        case let (.failed(m1), .failed(m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published var status: UpdateStatus = .idle

    private static let repo = "gramanoid/focuslens"
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    private(set) var lastDownloadedDMG: URL?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Check

    func checkForUpdates() async {
        status = .checking
        do {
            var request = URLRequest(url: Self.apiURL)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                status = .failed("GitHub API returned an error.")
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            guard Self.isNewer(remote: remoteVersion, local: currentVersion) else {
                status = .upToDate
                return
            }

            guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
                status = .failed("No DMG found in release \(release.tagName).")
                return
            }

            guard let downloadURL = URL(string: dmgAsset.browserDownloadURL) else {
                status = .failed("Invalid download URL.")
                return
            }

            status = .available(
                version: remoteVersion,
                notes: release.body ?? "",
                downloadURL: downloadURL
            )
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Download & Install

    func downloadAndInstall(url: URL) async {
        status = .downloading(progress: 0)
        do {
            let tempDMG = try await downloadDMG(from: url)
            lastDownloadedDMG = tempDMG
            status = .installing
            try await installFromDMG(tempDMG)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func retryInstall() async {
        guard let dmg = lastDownloadedDMG, FileManager.default.fileExists(atPath: dmg.path) else {
            status = .failed("Downloaded DMG not found. Please download again.")
            return
        }
        status = .installing
        do {
            try await installFromDMG(dmg)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func downloadDMG(from url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent("FocusLens-update.dmg")

        // Remove stale download
        try? FileManager.default.removeItem(at: destination)

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let expectedLength = http.expectedContentLength
        var data = Data()
        data.reserveCapacity(expectedLength > 0 ? Int(expectedLength) : 5_000_000)

        for try await byte in asyncBytes {
            data.append(byte)
            if expectedLength > 0, data.count % 65536 == 0 {
                let progress = Double(data.count) / Double(expectedLength)
                status = .downloading(progress: min(progress, 0.99))
            }
        }

        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func installFromDMG(_ dmgPath: URL) async throws {
        let mountPoint = try mountDMG(dmgPath)
        defer { detachDMG(mountPoint) }

        // Find .app in mounted volume
        let contents = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.noAppInDMG
        }

        let sourceApp = URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)
        let currentBundlePath = Bundle.main.bundlePath
        let destinationApp = URL(fileURLWithPath: currentBundlePath)

        // Replace current app bundle
        let backupPath = destinationApp.deletingLastPathComponent().appendingPathComponent("FocusLens-old.app")
        try? FileManager.default.removeItem(at: backupPath)

        // Move current → backup, copy new → current
        try FileManager.default.moveItem(at: destinationApp, to: backupPath)
        do {
            try FileManager.default.copyItem(at: sourceApp, to: destinationApp)
        } catch {
            // Restore backup on failure
            try? FileManager.default.moveItem(at: backupPath, to: destinationApp)
            throw error
        }

        // Clean up backup and temp DMG
        try? FileManager.default.removeItem(at: backupPath)
        try? FileManager.default.removeItem(at: dmgPath)

        // Relaunch
        relaunch(at: destinationApp.path)
    }

    private func mountDMG(_ path: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-plist", "-mountrandom", "/tmp"]
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let outData = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.mountFailedDetail(errText.isEmpty ? "hdiutil exited with code \(process.terminationStatus)" : errText)
        }

        // Parse plist output for mount point
        guard let plist = try? PropertyListSerialization.propertyList(from: outData, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            // Fallback: parse tab-separated text output
            let output = String(data: outData, encoding: .utf8) ?? ""
            guard let mountLine = output.split(separator: "\n").last,
                  let lastCol = mountLine.split(separator: "\t").last else {
                throw UpdateError.mountFailedDetail("Could not find mount point in hdiutil output")
            }
            return String(lastCol).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return mountPoint
    }

    private func detachDMG(_ mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func relaunch(at path: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Use a shell script that waits for our process to exit, then opens the new app
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        open "\(path)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()

        // Exit current app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Version Comparison

    static func isNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

// MARK: - Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum UpdateError: LocalizedError {
    case downloadFailed
    case mountFailedDetail(String)
    case noAppInDMG

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Failed to download the update."
        case .mountFailedDetail(let detail): "Failed to open DMG: \(detail)"
        case .noAppInDMG: "No application found in the update package."
        }
    }
}

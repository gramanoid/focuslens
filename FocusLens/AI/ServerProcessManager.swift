import AppKit
import Foundation

enum ServerProcessStatus: Equatable {
    case stopped
    case starting
    case running
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .running: true
        default: false
        }
    }
}

@MainActor
final class ServerProcessManager: ObservableObject {
    @Published var status: ServerProcessStatus = .stopped
    @Published var lastStdErr: String = ""

    private(set) var llamaServerPath: String?
    private var process: Process?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    init() {
        discoverLlamaServer()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    var isLlamaServerInstalled: Bool {
        llamaServerPath != nil
    }

    func start(model: ModelDefinition, port: Int = 8080) {
        guard let serverPath = llamaServerPath else {
            status = .failed("llama-server not found. Install: brew install llama.cpp")
            return
        }
        guard model.id == "custom" || model.isDownloaded else {
            status = .failed("Model files not downloaded.")
            return
        }

        stop()
        status = .starting
        lastStdErr = ""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)

        var args = [
            "-m", model.modelPath,
            "--mmproj", model.mmprojPath,
            "--port", "\(port)",
            "-ngl", "99"
        ]
        if model.imageMinTokens > 0 {
            args += ["--image-min-tokens", "\(model.imageMinTokens)"]
        }
        proc.arguments = args

        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        stderrPipe = errPipe

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — pipe closed (process exited). Clear handler to prevent spin-loop.
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastStdErr += text
                if self.lastStdErr.count > 2000 {
                    self.lastStdErr = String(self.lastStdErr.suffix(2000))
                }
            }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: proc,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process === proc else { return }
                // Clean up pipe handler to prevent spin-loop on EOF
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                let code = proc.terminationStatus
                if code != 0 && self.status != .stopped {
                    self.status = .failed("llama-server exited (\(code))")
                } else {
                    self.status = .stopped
                }
                self.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.process === proc, self.status == .starting else { return }
                self.status = .running
            }
        } catch {
            status = .failed("Launch failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak proc] in
                if let proc, proc.isRunning { proc.interrupt() }
            }
        }

        // Always clean up resources regardless of process state
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        terminationObserver = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        process = nil
        if status != .stopped { status = .stopped }
    }

    func restart(model: ModelDefinition, port: Int = 8080) {
        stop()
        start(model: model, port: port)
    }

    private func discoverLlamaServer() {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["llama-server"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice

        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, which.terminationStatus == 0 {
                llamaServerPath = path
                return
            }
        } catch {}

        let brewPath = "/opt/homebrew/bin/llama-server"
        if FileManager.default.fileExists(atPath: brewPath) {
            llamaServerPath = brewPath
        }
    }
}

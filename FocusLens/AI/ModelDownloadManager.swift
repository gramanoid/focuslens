import Foundation

enum DownloadStatus: Equatable {
    case idle
    case downloading(file: String, progress: Double)
    case complete
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

@MainActor
final class ModelDownloadManager: ObservableObject {
    @Published var status: DownloadStatus = .idle
    @Published var overallProgress: Double = 0

    private var currentTask: URLSessionDownloadTask?
    private var session: URLSession?

    func download(_ model: ModelDefinition) async {
        guard !status.isDownloading else { return }
        guard model.id != "custom" else { return }

        do {
            try ModelDefinition.ensureModelsDirectory()
        } catch {
            status = .failed("Cannot create ~/models/: \(error.localizedDescription)")
            return
        }

        if let available = availableDiskSpace(), available < 5_000_000_000 {
            status = .failed("Less than 5 GB disk space available.")
            return
        }

        if !model.modelFileExists {
            status = .downloading(file: model.modelFileName, progress: 0)
            let ok = await downloadFile(
                from: model.modelURL,
                to: URL(fileURLWithPath: model.modelPath),
                progressWeight: 0.7,
                progressOffset: 0
            )
            guard ok else { return }
        }

        if !model.mmprojFileExists {
            status = .downloading(file: model.mmprojFileName, progress: 0)
            let ok = await downloadFile(
                from: model.mmprojURL,
                to: URL(fileURLWithPath: model.mmprojPath),
                progressWeight: 0.3,
                progressOffset: 0.7
            )
            guard ok else { return }
        }

        status = .complete
        overallProgress = 1.0
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        status = .idle
        overallProgress = 0
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        progressWeight: Double,
        progressOffset: Double
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let delegate = DownloadDelegate(
                destination: destination,
                onProgress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.overallProgress = progressOffset + fraction * progressWeight
                        self.status = .downloading(
                            file: destination.lastPathComponent,
                            progress: fraction
                        )
                    }
                },
                onComplete: { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let error {
                            self?.status = .failed(error.localizedDescription)
                        }
                    }
                    continuation.resume(returning: error == nil)
                }
            )
            let urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.session = urlSession
            let task = urlSession.downloadTask(with: url)
            self.currentTask = task
            task.resume()
        }
    }

    private func availableDiskSpace() -> UInt64? {
        let url = ModelDefinition.modelsDirectoryURL()
        let values = try? (url as NSURL).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values?[.volumeAvailableCapacityForImportantUsageKey] as? Int64 else { return nil }
        return UInt64(capacity)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let onProgress: (Double) -> Void
    let onComplete: (Error?) -> Void
    private var completed = false

    init(destination: URL, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            completed = true
            onComplete(nil)
        } catch {
            onComplete(error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        if let error {
            onComplete(error)
        }
    }
}

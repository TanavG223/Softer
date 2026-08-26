import Foundation

final class ModelPackDownloader: NSObject, ModelPackDownloading, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private struct ActiveDownload {
        let artifact: ModelPackArtifact
        let destinationURL: URL
        let resumeDataURL: URL
        let task: URLSessionDownloadTask
        let continuation: CheckedContinuation<Void, Error>
        let progress: @Sendable (Int64) async -> Void
        var movedDownload = false
        var forcedFailure: ModelPackFailure?
    }

    private let fileManager: FileManager
    private let lock = NSLock()
    private var active: ActiveDownload?
    private var session: URLSession?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

    func download(
        _ artifact: ModelPackArtifact,
        to destinationURL: URL,
        resumeDataURL: URL,
        networkPolicy: ModelPackNetworkPolicy,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        guard Self.isApprovedSourceURL(artifact.sourceURL) else {
            if artifact.sourceURL.scheme?.lowercased() != "https" {
                throw ModelPackFailure.insecureURL
            }
            throw ModelPackFailure.unapprovedHost(artifact.sourceURL.host ?? "unknown")
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let configuration = Self.ephemeralConfiguration(for: networkPolicy)
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: nil
                )
                let task: URLSessionDownloadTask
                if let resumeData = try? Data(contentsOf: resumeDataURL), !resumeData.isEmpty {
                    task = session.downloadTask(withResumeData: resumeData)
                } else {
                    task = session.downloadTask(with: Self.request(for: artifact))
                }

                let accepted = withLock { () -> Bool in
                    guard active == nil else { return false }
                    self.session = session
                    active = ActiveDownload(
                        artifact: artifact,
                        destinationURL: destinationURL,
                        resumeDataURL: resumeDataURL,
                        task: task,
                        continuation: continuation,
                        progress: progress
                    )
                    return true
                }

                guard accepted else {
                    session.invalidateAndCancel()
                    continuation.resume(throwing: ModelPackFailure.alreadyInstalling)
                    return
                }
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        let cancellationTarget = withLock {
            active.map { ($0.task, $0.resumeDataURL) }
        }
        guard let (task, resumeURL) = cancellationTarget else { return }
        task.cancel { [weak self] resumeData in
            guard let self, let resumeData, !resumeData.isEmpty else { return }
            try? self.persistResumeData(resumeData, at: resumeURL)
        }
    }

    static func request(for artifact: ModelPackArtifact) -> URLRequest {
        var request = URLRequest(
            url: artifact.sourceURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 60
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("PaceBack-iOS-model-installer/1", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func ephemeralConfiguration(
        for policy: ModelPackNetworkPolicy
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.allowsCellularAccess = policy.allowsCellularAccess
        configuration.allowsExpensiveNetworkAccess = policy.allowsCellularAccess
        configuration.allowsConstrainedNetworkAccess = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        return configuration
    }

    static func isApprovedSourceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "huggingface.co"
    }

    static func isApprovedNetworkURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "huggingface.co" || host.hasSuffix(".hf.co")
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let callback = withLock { () -> (@Sendable (Int64) async -> Void)? in
            guard var active, active.task.taskIdentifier == downloadTask.taskIdentifier else {
                return nil
            }
            if totalBytesWritten > active.artifact.sizeBytes {
                active.forcedFailure = .sizeMismatch(
                    artifact: active.artifact.displayName,
                    expected: active.artifact.sizeBytes,
                    actual: totalBytesWritten
                )
                self.active = active
                downloadTask.cancel()
                return nil
            }
            return active.progress
        }
        if let callback {
            Task(priority: .utility) {
                await callback(totalBytesWritten)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let target = withLock { () -> (URL, ModelPackFailure?)? in
            guard let active, active.task.taskIdentifier == downloadTask.taskIdentifier else {
                return nil
            }
            if let failure = active.forcedFailure {
                return (active.destinationURL, failure)
            }
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                return (active.destinationURL, .invalidHTTPStatus(response.statusCode))
            }
            guard let finalURL = downloadTask.response?.url,
                  Self.isApprovedNetworkURL(finalURL) else {
                let host = downloadTask.response?.url?.host ?? "unknown"
                return (active.destinationURL, .unapprovedRedirect(host))
            }
            return (active.destinationURL, nil)
        }
        guard let (destinationURL, failure) = target else { return }
        if let failure {
            withLock {
                active?.forcedFailure = failure
            }
            return
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            withLock { active?.movedDownload = true }
        } catch {
            withLock {
                active?.forcedFailure = .fileSystem(error.localizedDescription)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectURL = request.url, Self.isApprovedNetworkURL(redirectURL) else {
            let host = request.url?.host ?? "unknown"
            withLock {
                active?.forcedFailure = .unapprovedRedirect(host)
            }
            completionHandler(nil)
            task.cancel()
            return
        }

        var sanitized = request
        sanitized.httpShouldHandleCookies = false
        sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
        sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(sanitized)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let finished = withLock { () -> ActiveDownload? in
            guard let active, active.task.taskIdentifier == task.taskIdentifier else {
                return nil
            }
            self.active = nil
            self.session = nil
            return active
        }
        guard let finished else { return }
        session.finishTasksAndInvalidate()

        if let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           !resumeData.isEmpty {
            try? persistResumeData(resumeData, at: finished.resumeDataURL)
        }

        if let failure = finished.forcedFailure {
            finished.continuation.resume(throwing: failure)
        } else if let urlError = error as? URLError, urlError.code == .cancelled {
            finished.continuation.resume(throwing: CancellationError())
        } else if let error {
            finished.continuation.resume(
                throwing: ModelPackFailure.downloadFailed(
                    artifact: finished.artifact.displayName,
                    reason: error.localizedDescription
                )
            )
        } else if finished.movedDownload {
            finished.continuation.resume()
        } else {
            finished.continuation.resume(
                throwing: ModelPackFailure.downloadFailed(
                    artifact: finished.artifact.displayName,
                    reason: "The download ended without a local file."
                )
            )
        }
    }

    private func persistResumeData(_ data: Data, at url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    @discardableResult
    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

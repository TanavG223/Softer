import CryptoKit
import Foundation

protocol ModelPackProviding: Sendable {
    func installedRootURL() throws -> URL
}

enum ModelPackNetworkPolicy: String, CaseIterable, Identifiable, Sendable {
    case wifiOnly
    case wifiAndCellular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifiOnly: "Wi-Fi only"
        case .wifiAndCellular: "Wi-Fi or cellular"
        }
    }

    var detail: String {
        switch self {
        case .wifiOnly:
            "Waits for Wi-Fi and never uses cellular data."
        case .wifiAndCellular:
            "Allows up to 157,716,998 bytes of cellular data for this install."
        }
    }

    var allowsCellularAccess: Bool { self == .wifiAndCellular }
}

struct ModelPackArtifact: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let relativePath: String
    let sourceURL: URL
    let sha256: String
    let sizeBytes: Int64
}

enum PaceBackModelPack {
    static let packID = "paceback-bge-small-minilm-onnx-v1"
    static let formatVersion = 1
    static let denseRevision = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
    static let rerankerRevision = "233902d25c440f23af6f7d6e94d2946bac0bee0a"
    static let totalSizeBytes: Int64 = 157_716_998
    static let stagingHeadroomBytes: Int64 = 64 * 1_024 * 1_024
    static let largestArtifactBytes: Int64 = 133_093_490
    static let minimumFreeSpaceBytes = totalSizeBytes + largestArtifactBytes + stagingHeadroomBytes

    static let artifacts: [ModelPackArtifact] = [
        ModelPackArtifact(
            id: "dense-model",
            displayName: "Meaning search weights",
            relativePath: "dense/model.onnx",
            sourceURL: URL(
                string: "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/\(denseRevision)/onnx/model.onnx"
            )!,
            sha256: "828e1496d7fabb79cfa4dcd84fa38625c0d3d21da474a00f08db0f559940cf35",
            sizeBytes: 133_093_490
        ),
        ModelPackArtifact(
            id: "dense-tokenizer",
            displayName: "Meaning search tokenizer",
            relativePath: "dense/tokenizer.json",
            sourceURL: URL(
                string: "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/\(denseRevision)/tokenizer.json"
            )!,
            sha256: "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66",
            sizeBytes: 711_396
        ),
        ModelPackArtifact(
            id: "reranker-model",
            displayName: "Evidence reranker weights",
            relativePath: "reranker/model.onnx",
            sourceURL: URL(
                string: "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2/resolve/\(rerankerRevision)/onnx/model_qint8_arm64.onnx"
            )!,
            sha256: "3573b6b9593cb2f75987a31815d409ca3dd8808629118fd20451bb1a5d90cec7",
            sizeBytes: 23_200_716
        ),
        ModelPackArtifact(
            id: "reranker-tokenizer",
            displayName: "Evidence reranker tokenizer",
            relativePath: "reranker/tokenizer.json",
            sourceURL: URL(
                string: "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2/resolve/\(rerankerRevision)/tokenizer.json"
            )!,
            sha256: "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66",
            sizeBytes: 711_396
        ),
    ]
}

struct ModelPackDescriptor: Sendable {
    let packID: String
    let formatVersion: Int
    let denseModelID: String
    let denseRevision: String
    let rerankerModelID: String
    let rerankerRevision: String
    let artifacts: [ModelPackArtifact]
    let totalSizeBytes: Int64
    let minimumFreeSpaceBytes: Int64

    static let production = ModelPackDescriptor(
        packID: PaceBackModelPack.packID,
        formatVersion: PaceBackModelPack.formatVersion,
        denseModelID: "BAAI/bge-small-en-v1.5",
        denseRevision: PaceBackModelPack.denseRevision,
        rerankerModelID: "cross-encoder/ms-marco-MiniLM-L-6-v2",
        rerankerRevision: PaceBackModelPack.rerankerRevision,
        artifacts: PaceBackModelPack.artifacts,
        totalSizeBytes: PaceBackModelPack.totalSizeBytes,
        minimumFreeSpaceBytes: PaceBackModelPack.minimumFreeSpaceBytes
    )
}

struct ModelPackArtifactProgress: Identifiable, Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case pending
        case downloading
        case verified
    }

    let id: String
    let name: String
    let receivedBytes: Int64
    let expectedBytes: Int64
    let state: State

    var fractionCompleted: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }
}

struct ModelPackProgress: Equatable, Sendable {
    let artifacts: [ModelPackArtifactProgress]
    let receivedBytes: Int64
    let expectedBytes: Int64

    var fractionCompleted: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }
}

struct ModelPackCapacity: Equatable, Sendable {
    let availableBytes: Int64
    let requiredBytes: Int64

    var hasEnoughSpace: Bool { availableBytes >= requiredBytes }
}

struct ModelPackReceipt: Equatable, Sendable {
    let packID: String
    let installedBytes: Int64
    let rootURL: URL
}

enum ModelPackFailure: Error, Equatable, Sendable {
    case missingTrustMaterial
    case invalidManifestSignature
    case unexpectedManifest
    case insecureURL
    case unapprovedHost(String)
    case unapprovedRedirect(String)
    case invalidHTTPStatus(Int)
    case insufficientSpace(required: Int64, available: Int64)
    case sizeMismatch(artifact: String, expected: Int64, actual: Int64)
    case hashMismatch(artifact: String)
    case corruptInstallation
    case alreadyInstalling
    case downloadFailed(artifact: String, reason: String)
    case fileSystem(String)
}

extension ModelPackFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingTrustMaterial:
            "The signed model manifest or public verification key is missing. Reinstall PaceBack."
        case .invalidManifestSignature:
            "The model manifest signature is invalid. Nothing was installed."
        case .unexpectedManifest:
            "The signed manifest does not match PaceBack’s pinned model pack."
        case .insecureURL:
            "PaceBack refused a model download that was not protected by HTTPS."
        case .unapprovedHost(let host):
            "PaceBack refused the unapproved download host \(host)."
        case .unapprovedRedirect(let host):
            "PaceBack stopped an unexpected redirect to \(host)."
        case .invalidHTTPStatus(let status):
            "The model host returned HTTP \(status). Try again later."
        case .insufficientSpace(let required, let available):
            "This install needs \(required.formatted(.byteCount(style: .file))) free; \(available.formatted(.byteCount(style: .file))) is available."
        case .sizeMismatch(let artifact, let expected, let actual):
            "\(artifact) had the wrong size (expected \(expected) bytes, received \(actual)). Nothing was activated."
        case .hashMismatch(let artifact):
            "\(artifact) failed its SHA-256 integrity check. Nothing was activated."
        case .corruptInstallation:
            "The installed model pack did not pass verification. Delete it and install again."
        case .alreadyInstalling:
            "A model installation is already in progress."
        case .downloadFailed(let artifact, let reason):
            "\(artifact) could not be downloaded: \(reason)"
        case .fileSystem(let reason):
            "The local model folder could not be prepared: \(reason)"
        }
    }
}

enum ModelPackStatus: Equatable, Sendable {
    case checking
    case notInstalled
    case preparing(ModelPackCapacity)
    case downloading(ModelPackProgress)
    case verifying(completedArtifacts: Int, totalArtifacts: Int)
    case paused(ModelPackProgress)
    case ready(ModelPackReceipt)
    case failed(ModelPackFailure)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isWorking: Bool {
        switch self {
        case .preparing, .downloading, .verifying:
            true
        default:
            false
        }
    }
}

struct ModelPackTrustMaterial: Sendable {
    let manifestData: Data
    let publicKeyData: Data
}

protocol ModelPackTrustMaterialProviding: Sendable {
    func loadTrustMaterial() throws -> ModelPackTrustMaterial
}

struct BundledModelPackTrustMaterialProvider: ModelPackTrustMaterialProviding, @unchecked Sendable {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadTrustMaterial() throws -> ModelPackTrustMaterial {
        let manifestURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "ModelPack"
        ) ?? bundle.url(forResource: "manifest", withExtension: "json")
        let keyURL = bundle.url(
            forResource: "model-pack-trust-key",
            withExtension: "b64",
            subdirectory: "ModelPack"
        ) ?? bundle.url(forResource: "model-pack-trust-key", withExtension: "b64")

        guard let manifestURL, let keyURL else {
            throw ModelPackFailure.missingTrustMaterial
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let encodedKey = try String(contentsOf: keyURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let publicKeyData = Data(base64Encoded: encodedKey) else {
            throw ModelPackFailure.missingTrustMaterial
        }
        return ModelPackTrustMaterial(manifestData: manifestData, publicKeyData: publicKeyData)
    }
}

struct FixedModelPackTrustMaterialProvider: ModelPackTrustMaterialProviding {
    let material: ModelPackTrustMaterial

    func loadTrustMaterial() throws -> ModelPackTrustMaterial { material }
}

struct ModelPackTrustValidator: Sendable {
    let descriptor: ModelPackDescriptor

    init(descriptor: ModelPackDescriptor = .production) {
        self.descriptor = descriptor
    }

    func validateTrustMaterial(_ material: ModelPackTrustMaterial) throws {
        guard
            let object = try JSONSerialization.jsonObject(with: material.manifestData) as? [String: Any],
            let signatureObject = object["signature"] as? [String: Any],
            signatureObject["algorithm"] as? String == "ed25519",
            let encodedSignature = signatureObject["value"] as? String,
            let signature = Data(base64Encoded: encodedSignature)
        else {
            throw ModelPackFailure.unexpectedManifest
        }

        var unsigned = object
        unsigned.removeValue(forKey: "signature")
        let canonical = try JSONSerialization.data(
            withJSONObject: unsigned,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: material.publicKeyData)
        guard publicKey.isValidSignature(signature, for: canonical) else {
            throw ModelPackFailure.invalidManifestSignature
        }
        try validatePins(in: object)
    }

    func validateArtifact(_ artifact: ModelPackArtifact, at fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ModelPackFailure.sizeMismatch(
                artifact: artifact.displayName,
                expected: artifact.sizeBytes,
                actual: 0
            )
        }
        let actualSize = Int64(values.fileSize ?? 0)
        guard actualSize == artifact.sizeBytes else {
            throw ModelPackFailure.sizeMismatch(
                artifact: artifact.displayName,
                expected: artifact.sizeBytes,
                actual: actualSize
            )
        }
        guard try sha256(of: fileURL) == artifact.sha256 else {
            throw ModelPackFailure.hashMismatch(artifact: artifact.displayName)
        }
    }

    func validatePack(at rootURL: URL, material: ModelPackTrustMaterial) throws -> ModelPackReceipt {
        try validateTrustMaterial(material)
        let installedManifestURL = rootURL.appending(path: "manifest.json")
        let installedManifest = try Data(contentsOf: installedManifestURL)
        guard installedManifest == material.manifestData else {
            throw ModelPackFailure.corruptInstallation
        }
        for artifact in descriptor.artifacts {
            try validateArtifact(artifact, at: rootURL.appending(path: artifact.relativePath))
        }
        return ModelPackReceipt(
            packID: descriptor.packID,
            installedBytes: descriptor.totalSizeBytes,
            rootURL: rootURL
        )
    }

    private func validatePins(in manifest: [String: Any]) throws {
        guard
            manifest["formatVersion"] as? Int == descriptor.formatVersion,
            manifest["packID"] as? String == descriptor.packID,
            let components = manifest["components"] as? [String: Any],
            let dense = components["dense"] as? [String: Any],
            let reranker = components["reranker"] as? [String: Any],
            dense["modelID"] as? String == descriptor.denseModelID,
            dense["revision"] as? String == descriptor.denseRevision,
            reranker["modelID"] as? String == descriptor.rerankerModelID,
            reranker["revision"] as? String == descriptor.rerankerRevision
        else {
            throw ModelPackFailure.unexpectedManifest
        }

        for artifact in descriptor.artifacts {
            let parts = artifact.relativePath.split(separator: "/")
            guard
                parts.count == 2,
                let component = components[String(parts[0])] as? [String: Any],
                let artifactObject = component[String(parts[1]).hasPrefix("model") ? "model" : "tokenizer"] as? [String: Any],
                artifactObject["path"] as? String == artifact.relativePath,
                artifactObject["sha256"] as? String == artifact.sha256,
                let number = artifactObject["sizeBytes"] as? NSNumber,
                number.int64Value == artifact.sizeBytes
            else {
                throw ModelPackFailure.unexpectedManifest
            }
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let block = try handle.read(upToCount: 1_048_576) ?? Data()
            if block.isEmpty { break }
            digest.update(data: block)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

protocol ModelPackDiskCapacityProviding: Sendable {
    func availableCapacity(at url: URL) throws -> Int64
}

struct SystemModelPackDiskCapacityProvider: ModelPackDiskCapacityProviding {
    func availableCapacity(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        return Int64(values.volumeAvailableCapacity ?? 0)
    }
}

protocol ModelPackDownloading: Sendable {
    func download(
        _ artifact: ModelPackArtifact,
        to destinationURL: URL,
        resumeDataURL: URL,
        networkPolicy: ModelPackNetworkPolicy,
        progress: @escaping @Sendable (_ receivedBytes: Int64) async -> Void
    ) async throws

    func cancel()
}

final class ModelPackStore: ModelPackProviding, @unchecked Sendable {
    private struct LockedState {
        var verifiedRootURL: URL?
        var isInstalling = false
    }

    private let rootURL: URL
    private let downloader: any ModelPackDownloading
    private let capacityProvider: any ModelPackDiskCapacityProviding
    private let trustProvider: any ModelPackTrustMaterialProviding
    private let descriptor: ModelPackDescriptor
    private let validator: ModelPackTrustValidator
    private let fileManager: FileManager
    private let lock = NSLock()
    private var lockedState = LockedState()

    init(
        rootURL: URL = ModelPackStore.defaultRootURL(),
        downloader: any ModelPackDownloading = ModelPackDownloader(),
        capacityProvider: any ModelPackDiskCapacityProviding = SystemModelPackDiskCapacityProvider(),
        trustProvider: any ModelPackTrustMaterialProviding = BundledModelPackTrustMaterialProvider(),
        descriptor: ModelPackDescriptor = .production,
        validator: ModelPackTrustValidator? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.downloader = downloader
        self.capacityProvider = capacityProvider
        self.trustProvider = trustProvider
        self.descriptor = descriptor
        self.validator = validator ?? ModelPackTrustValidator(descriptor: descriptor)
        self.fileManager = fileManager
    }

    func installedRootURL() throws -> URL {
        let verifiedRoot = withLock { lockedState.verifiedRootURL }
        guard let verifiedRoot,
              fileManager.fileExists(atPath: verifiedRoot.path(percentEncoded: false)) else {
            throw ModelPackFailure.corruptInstallation
        }
        return verifiedRoot
    }

    func preflight() async -> Result<ModelPackCapacity, ModelPackFailure> {
        do {
            try await prepareContainer()
            let available = try await performFileIO {
                try self.capacityProvider.availableCapacity(at: self.rootURL)
            }
            let capacity = ModelPackCapacity(
                availableBytes: available,
                requiredBytes: descriptor.minimumFreeSpaceBytes
            )
            if !capacity.hasEnoughSpace {
                return .failure(
                    .insufficientSpace(required: capacity.requiredBytes, available: capacity.availableBytes)
                )
            }
            return .success(capacity)
        } catch let failure as ModelPackFailure {
            return .failure(failure)
        } catch {
            return .failure(.fileSystem(error.localizedDescription))
        }
    }

    func inspectInstallation() async -> ModelPackStatus {
        do {
            try await prepareContainer()
            let material = try trustProvider.loadTrustMaterial()
            let activeRoot = activeRootURL
            if fileManager.fileExists(atPath: activeRoot.path(percentEncoded: false)) {
                let receipt = try await performFileIO {
                    try self.validator.validatePack(at: activeRoot, material: material)
                }
                withLock { lockedState.verifiedRootURL = activeRoot }
                return .ready(receipt)
            }
            let progress = try await stagingProgress()
            return progress.receivedBytes > 0 ? .paused(progress) : .notInstalled
        } catch let failure as ModelPackFailure {
            withLock { lockedState.verifiedRootURL = nil }
            return .failed(failure)
        } catch {
            withLock { lockedState.verifiedRootURL = nil }
            return .failed(.corruptInstallation)
        }
    }

    func install(
        networkPolicy: ModelPackNetworkPolicy,
        force: Bool = false,
        onStatus: @escaping @Sendable (ModelPackStatus) async -> Void
    ) async -> ModelPackStatus {
        let began = withLock { () -> Bool in
            guard !lockedState.isInstalling else { return false }
            lockedState.isInstalling = true
            return true
        }
        guard began else { return .failed(.alreadyInstalling) }
        defer { withLock { lockedState.isInstalling = false } }

        do {
            let material = try trustProvider.loadTrustMaterial()
            try validator.validateTrustMaterial(material)
            try await prepareContainer()
            if force {
                try await performFileIO {
                    try self.removeIfPresent(self.stagingRootURL)
                    try self.removeIfPresent(self.resumeRootURL)
                }
            }

            let capacityResult = await preflight()
            let capacity = try capacityResult.get()
            await onStatus(.preparing(capacity))

            try await performFileIO {
                try self.fileManager.createDirectory(
                    at: self.stagingRootURL,
                    withIntermediateDirectories: true
                )
                try self.fileManager.createDirectory(
                    at: self.resumeRootURL,
                    withIntermediateDirectories: true
                )
            }

            let accumulator = ModelPackProgressAccumulator(descriptor: descriptor)
            for artifact in descriptor.artifacts {
                try Task.checkCancellation()
                let destination = stagingRootURL.appending(path: artifact.relativePath)
                let alreadyValid = await artifactIsValid(artifact, at: destination)
                if alreadyValid {
                    accumulator.markVerified(artifact)
                    await onStatus(.downloading(accumulator.snapshot()))
                    continue
                }

                try await performFileIO {
                    try self.removeIfPresent(destination)
                    try self.fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                }
                accumulator.begin(artifact)
                let resumeURL = resumeRootURL.appending(path: "\(artifact.id).resume")
                do {
                    try await downloader.download(
                        artifact,
                        to: destination,
                        resumeDataURL: resumeURL,
                        networkPolicy: networkPolicy
                    ) { received in
                        let snapshot = accumulator.update(artifact, receivedBytes: received)
                        await onStatus(.downloading(snapshot))
                    }
                } catch is CancellationError {
                    let paused = accumulator.snapshot()
                    await onStatus(.paused(paused))
                    return .paused(paused)
                } catch let failure as ModelPackFailure {
                    throw failure
                } catch {
                    throw ModelPackFailure.downloadFailed(
                        artifact: artifact.displayName,
                        reason: error.localizedDescription
                    )
                }

                try await performFileIO {
                    try self.validator.validateArtifact(artifact, at: destination)
                    try self.setFileProtection(at: destination)
                    try self.removeIfPresent(resumeURL)
                }
                accumulator.markVerified(artifact)
                await onStatus(.downloading(accumulator.snapshot()))
            }

            for completed in 0...descriptor.artifacts.count {
                await onStatus(
                    .verifying(
                        completedArtifacts: completed,
                        totalArtifacts: descriptor.artifacts.count
                    )
                )
                if completed < descriptor.artifacts.count {
                    let artifact = descriptor.artifacts[completed]
                    try await performFileIO {
                        try self.validator.validateArtifact(
                            artifact,
                            at: self.stagingRootURL.appending(path: artifact.relativePath)
                        )
                    }
                }
            }

            try await performFileIO {
                try material.manifestData.write(
                    to: self.stagingRootURL.appending(path: "manifest.json"),
                    options: [.atomic]
                )
                try self.setProtectionRecursively(at: self.stagingRootURL)
                _ = try self.validator.validatePack(at: self.stagingRootURL, material: material)
                try self.activateStaging()
            }
            let receipt = try await performFileIO {
                try self.validator.validatePack(at: self.activeRootURL, material: material)
            }
            withLock { lockedState.verifiedRootURL = activeRootURL }
            let ready = ModelPackStatus.ready(receipt)
            await onStatus(ready)
            return ready
        } catch is CancellationError {
            let progress = (try? await stagingProgress()) ?? ModelPackProgress.empty(descriptor: descriptor)
            let paused = ModelPackStatus.paused(progress)
            await onStatus(paused)
            return paused
        } catch let failure as ModelPackFailure {
            let failed = ModelPackStatus.failed(failure)
            await onStatus(failed)
            return failed
        } catch {
            let failed = ModelPackStatus.failed(.fileSystem(error.localizedDescription))
            await onStatus(failed)
            return failed
        }
    }

    func cancel() {
        downloader.cancel()
    }

    func deleteInstallation() async -> ModelPackStatus {
        downloader.cancel()
        withLock { lockedState.verifiedRootURL = nil }
        do {
            try await performFileIO {
                try self.removeIfPresent(self.activeRootURL)
                try self.removeIfPresent(self.stagingRootURL)
                try self.removeIfPresent(self.resumeRootURL)
            }
            return .notInstalled
        } catch {
            return .failed(.fileSystem(error.localizedDescription))
        }
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appending(path: "PaceBack", directoryHint: .isDirectory)
            .appending(path: "ModelPack-v1", directoryHint: .isDirectory)
    }

    private var activeRootURL: URL { rootURL.appending(path: "active", directoryHint: .isDirectory) }
    private var stagingRootURL: URL { rootURL.appending(path: "staging", directoryHint: .isDirectory) }
    private var resumeRootURL: URL { rootURL.appending(path: "resume", directoryHint: .isDirectory) }

    private func prepareContainer() async throws {
        try await performFileIO {
            try self.fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableRoot = self.rootURL
            try mutableRoot.setResourceValues(values)
            try self.setFileProtection(at: self.rootURL)
        }
    }

    private func stagingProgress() async throws -> ModelPackProgress {
        let accumulator = ModelPackProgressAccumulator(descriptor: descriptor)
        for artifact in descriptor.artifacts {
            let destination = stagingRootURL.appending(path: artifact.relativePath)
            if await artifactIsValid(artifact, at: destination) {
                accumulator.markVerified(artifact)
            }
        }
        return accumulator.snapshot()
    }

    private func artifactIsValid(_ artifact: ModelPackArtifact, at url: URL) async -> Bool {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        return (try? await performFileIO {
            try self.validator.validateArtifact(artifact, at: url)
        }) != nil
    }

    private func activateStaging() throws {
        let backupURL = rootURL.appending(path: "active-backup", directoryHint: .isDirectory)
        try removeIfPresent(backupURL)
        if fileManager.fileExists(atPath: activeRootURL.path(percentEncoded: false)) {
            try fileManager.moveItem(at: activeRootURL, to: backupURL)
        }
        do {
            try fileManager.moveItem(at: stagingRootURL, to: activeRootURL)
            try removeIfPresent(backupURL)
            try removeIfPresent(resumeRootURL)
        } catch {
            try? removeIfPresent(activeRootURL)
            if fileManager.fileExists(atPath: backupURL.path(percentEncoded: false)) {
                try? fileManager.moveItem(at: backupURL, to: activeRootURL)
            }
            throw error
        }
    }

    private func setProtectionRecursively(at root: URL) throws {
        try setFileProtection(at: root)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let item as URL in enumerator {
            try setFileProtection(at: item)
        }
    }

    private func setFileProtection(at url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
        }
    }

    private func performFileIO<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .utility, operation: operation).value
    }

    @discardableResult
    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private final class ModelPackProgressAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let descriptor: ModelPackDescriptor
    private var progressByID: [String: ModelPackArtifactProgress]

    init(descriptor: ModelPackDescriptor) {
        self.descriptor = descriptor
        progressByID = Dictionary(
            uniqueKeysWithValues: descriptor.artifacts.map {
                (
                    $0.id,
                    ModelPackArtifactProgress(
                        id: $0.id,
                        name: $0.displayName,
                        receivedBytes: 0,
                        expectedBytes: $0.sizeBytes,
                        state: .pending
                    )
                )
            }
        )
    }

    func begin(_ artifact: ModelPackArtifact) {
        updateValue(for: artifact, receivedBytes: 0, state: .downloading)
    }

    func markVerified(_ artifact: ModelPackArtifact) {
        updateValue(for: artifact, receivedBytes: artifact.sizeBytes, state: .verified)
    }

    func update(_ artifact: ModelPackArtifact, receivedBytes: Int64) -> ModelPackProgress {
        updateValue(
            for: artifact,
            receivedBytes: min(max(receivedBytes, 0), artifact.sizeBytes),
            state: .downloading
        )
        return snapshot()
    }

    func snapshot() -> ModelPackProgress {
        lock.lock()
        defer { lock.unlock() }
        let ordered = descriptor.artifacts.compactMap { progressByID[$0.id] }
        return ModelPackProgress(
            artifacts: ordered,
            receivedBytes: ordered.reduce(0) { $0 + $1.receivedBytes },
            expectedBytes: descriptor.totalSizeBytes
        )
    }

    private func updateValue(
        for artifact: ModelPackArtifact,
        receivedBytes: Int64,
        state: ModelPackArtifactProgress.State
    ) {
        lock.lock()
        progressByID[artifact.id] = ModelPackArtifactProgress(
            id: artifact.id,
            name: artifact.displayName,
            receivedBytes: receivedBytes,
            expectedBytes: artifact.sizeBytes,
            state: state
        )
        lock.unlock()
    }
}

private extension ModelPackProgress {
    static func empty(descriptor: ModelPackDescriptor) -> ModelPackProgress {
        ModelPackProgress(
            artifacts: descriptor.artifacts.map {
                ModelPackArtifactProgress(
                    id: $0.id,
                    name: $0.displayName,
                    receivedBytes: 0,
                    expectedBytes: $0.sizeBytes,
                    state: .pending
                )
            },
            receivedBytes: 0,
            expectedBytes: descriptor.totalSizeBytes
        )
    }
}

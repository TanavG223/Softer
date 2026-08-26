import Foundation
import Observation
import OSLog
import Security

public actor SwitchingAIEngine: AIEngine {
    private var active: any AIEngine
    private var desiredProfiles: [UUID: LocalProfile] = [:]
    private var tombstones: [UUID: ActingRole] = [:]

    public init(fallback: any AIEngine = UnavailableAIEngine()) {
        self.active = fallback
    }

    public func install(_ engine: any AIEngine) async throws {
        active = engine
        for profileID in tombstones.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let actingRole = tombstones[profileID] else { continue }
            try await active.deleteProfile(id: profileID, actingRole: actingRole)
        }
        for profileID in desiredProfiles.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let profile = desiredProfiles[profileID] else { continue }
            try await active.syncProfile(profile)
        }
    }

    public func health() async throws -> EngineHealth {
        try await active.health()
    }

    public func ask(_ query: EvidenceQuery) async throws -> EvidenceAnswer {
        try await active.ask(query)
    }

    public func syncProfile(_ profile: LocalProfile) async throws {
        desiredProfiles[profile.id] = profile
        tombstones.removeValue(forKey: profile.id)
        try await active.syncProfile(profile)
    }

    public func deleteProfile(id: UUID, actingRole: ActingRole) async throws {
        desiredProfiles.removeValue(forKey: id)
        tombstones[id] = actingRole
        try await active.deleteProfile(id: id, actingRole: actingRole)
    }

    public func cancel(runID: String, profileID: UUID) async {
        await active.cancel(runID: runID, profileID: profileID)
    }
}

public enum SidecarRuntimeState: Equatable, Sendable {
    case idle
    case starting
    case connected(port: Int)
    case unavailable(reason: String)
    case stopped
}

public enum SidecarRuntimeError: LocalizedError, Sendable {
    case helperUnavailable
    case invalidCodeSignature(OSStatus)
    case signingIdentityMismatch
    case modelPackUnavailable
    case invalidHandshake
    case helperExited(Int32)
    case randomGeneration(OSStatus)
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "The bundled local evidence helper is unavailable."
        case .invalidCodeSignature(let status):
            "The bundled local evidence helper failed code-signature validation (\(status))."
        case .signingIdentityMismatch:
            "The bundled local evidence helper is not signed by the expected developer."
        case .modelPackUnavailable:
            "The signed local BGE and MiniLM model pack is missing or invalid."
        case .invalidHandshake:
            "The local evidence helper returned an invalid startup handshake."
        case .helperExited(let code):
            "The local evidence helper exited during startup (code \(code))."
        case .randomGeneration(let status):
            "Secure random generation failed (\(status))."
        case .keychain(let status):
            "The engine encryption key could not be accessed (\(status))."
        }
    }
}

@MainActor
@Observable
public final class SidecarEngineRuntime {
    private static let logger = Logger(
        subsystem: "org.hackforhumanity.paceback",
        category: "LocalEvidenceEngine"
    )

    public let engine: SwitchingAIEngine
    public private(set) var state: SidecarRuntimeState = .idle

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var inputPipe: Pipe?
    @ObservationIgnored private let environment: [String: String]

    public init(
        engine: SwitchingAIEngine = SwitchingAIEngine(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.engine = engine
        self.environment = environment
    }

    public func start() async {
        guard state == .idle || state == .stopped else { return }
        state = .starting
        do {
            let resolvedHelper = try resolveHelper()
            if resolvedHelper.isBundled {
                try Self.validateBundledHelperSignature(at: resolvedHelper.url)
            }
            let authToken = try Self.randomSecret()
            // Keychain access can synchronously wait on securityd or user
            // interaction. Keep it off the main actor so the first window and
            // its explicit "starting" state remain responsive.
            let databaseKey = try await Task.detached(priority: .userInitiated) {
                try EngineStorageKeyStore().loadOrCreate()
            }.value
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = resolvedHelper.url
            let storageDirectory = try Self.engineStorageDirectory()
            var arguments = ["--data-dir", storageDirectory.path]
            if resolvedHelper.developmentOverrideActive {
                arguments.append("--development")
            }
            process.arguments = arguments
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.environment = try childEnvironment(for: resolvedHelper)
            process.terminationHandler = { [weak self] terminated in
                Task { @MainActor [weak self] in
                    guard let self, self.process === terminated else { return }
                    self.process = nil
                    self.inputPipe = nil
                    try? await self.engine.install(UnavailableAIEngine())
                    if self.state != .stopped {
                        self.state = .unavailable(
                            reason: SidecarRuntimeError.helperExited(terminated.terminationStatus)
                                .localizedDescription
                        )
                    }
                }
            }
            try process.run()
            self.process = process
            self.inputPipe = input

            let payload = ["authToken": authToken, "databaseKey": databaseKey]
            let data = try JSONSerialization.data(withJSONObject: payload)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))

            let handshakeData = try await Self.readStartupLine(
                from: output.fileHandleForReading,
                process: process
            )
            let handshake = try JSONDecoder().decode(SidecarHandshake.self, from: handshakeData)
            guard handshake.protocolVersion == "v1",
                  handshake.ready,
                  (1...65_535).contains(handshake.port),
                  handshake.pid == process.processIdentifier else {
                throw SidecarRuntimeError.invalidHandshake
            }
            let client = try URLSidecarAIEngine(
                baseURL: URL(string: "http://127.0.0.1:\(handshake.port)/")!,
                bearerToken: authToken
            )
            let health = try await client.health()
            try Self.validateHealth(
                health,
                developmentOverrideActive: resolvedHelper.developmentOverrideActive
            )
            if resolvedHelper.isBundled {
                try Self.validateModelManifest(try await client.modelManifest())
            }
            try await engine.install(client)
            state = .connected(port: handshake.port)
        } catch {
            Self.logger.error(
                "Local evidence helper failed closed: \(error.localizedDescription, privacy: .public)"
            )
            stopProcess()
            try? await engine.install(UnavailableAIEngine())
            state = .unavailable(reason: error.localizedDescription)
        }
    }

    public func stop() {
        state = .stopped
        stopProcess()
    }

    private func stopProcess() {
        try? inputPipe?.fileHandleForWriting.close()
        inputPipe = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    private struct ResolvedHelper {
        let url: URL
        let isBundled: Bool
        let developmentOverrideActive: Bool
    }

    private func resolveHelper() throws -> ResolvedHelper {
        #if DEBUG
        if let configured = environment["PACEBACK_ENGINE_EXECUTABLE"], !configured.isEmpty {
            let url = URL(filePath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw SidecarRuntimeError.helperUnavailable
            }
            return ResolvedHelper(
                url: url,
                isBundled: false,
                developmentOverrideActive: environment["PACEBACK_ENGINE_DEVELOPMENT"] == "1"
            )
        }
        #endif

        let fixedBundledHelper = Bundle.main.bundleURL
            .appending(
                path: "Contents/Helpers/PaceBackEngine.app/Contents/MacOS/paceback-engine",
                directoryHint: .notDirectory
            )

        #if !DEBUG
        guard FileManager.default.isExecutableFile(atPath: fixedBundledHelper.path) else {
            throw SidecarRuntimeError.helperUnavailable
        }
        return ResolvedHelper(
            url: fixedBundledHelper,
            isBundled: true,
            developmentOverrideActive: false
        )
        #else
        let candidates = [
            fixedBundledHelper,
            Bundle.main.url(forAuxiliaryExecutable: "paceback-engine"),
            Bundle.main.bundleURL
                .appending(path: "Contents/Helpers/paceback-engine", directoryHint: .notDirectory),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appending(path: "paceback-engine", directoryHint: .notDirectory)
        ].compactMap { $0 }
        guard let helper = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw SidecarRuntimeError.helperUnavailable
        }
        return ResolvedHelper(
            url: helper,
            isBundled: helper.path.hasPrefix(Bundle.main.bundleURL.path),
            developmentOverrideActive: environment["PACEBACK_ENGINE_DEVELOPMENT"] == "1"
        )
        #endif
    }

    nonisolated static func validateHealth(
        _ health: EngineHealth,
        developmentOverrideActive: Bool
    ) throws {
        guard health.status == "ok",
              isSupportedEngineVersion(health.version),
              health.databaseReady,
              health.fts5Ready,
              !health.networkToolsEnabled else {
            throw SidecarRuntimeError.invalidHandshake
        }

        let isEncryptedRelease = health.releaseMode &&
            health.storageDriver == "sqlcipher" &&
            health.storageEncryptionActive

        #if DEBUG
        let isExplicitDevelopmentStorage = developmentOverrideActive &&
            !health.releaseMode &&
            health.storageDriver == "sqlite" &&
            !health.storageEncryptionActive
        guard isEncryptedRelease || isExplicitDevelopmentStorage else {
            throw SidecarRuntimeError.invalidHandshake
        }
        #else
        guard !developmentOverrideActive, isEncryptedRelease else {
            throw SidecarRuntimeError.invalidHandshake
        }
        #endif
    }

    nonisolated static func isSupportedEngineVersion(_ version: String) -> Bool {
        let core = version.split(separator: "-", maxSplits: 1).first ?? ""
        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "0",
              components[1] == "1",
              let patch = Int(components[2]),
              patch >= 0 else {
            return false
        }
        return true
    }

    nonisolated static func validateModelManifest(_ manifest: EngineModelManifest) throws {
        guard manifest.modelPackActivation == "active",
              manifest.modelPackID == "paceback-bge-small-minilm-onnx-v1",
              !manifest.webSearchEnabled,
              !manifest.codeExecutionEnabled,
              !manifest.runtimeWeightUpdatesEnabled,
              manifest.storageDriver == "sqlcipher",
              manifest.storageEncryptionActive else {
            throw SidecarRuntimeError.invalidHandshake
        }

        let dense = manifest.components.first { $0.name == "bge-small-en-v1.5-onnx" }
        let reranker = manifest.components.first { $0.name == "ms-marco-MiniLM-L6-v2-onnx" }
        guard let dense,
              dense.active,
              dense.activation == "active",
              dense.localOnly,
              dense.modelID == "BAAI/bge-small-en-v1.5",
              dense.revision == "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a",
              dense.dimensions == 384,
              dense.provider == "CPUExecutionProvider",
              dense.artifactSHA256?.count == 64,
              let reranker,
              reranker.active,
              reranker.activation == "active",
              reranker.localOnly,
              reranker.modelID == "cross-encoder/ms-marco-MiniLM-L-6-v2",
              reranker.revision == "233902d25c440f23af6f7d6e94d2946bac0bee0a",
              reranker.provider == "CPUExecutionProvider",
              reranker.artifactSHA256?.count == 64 else {
            throw SidecarRuntimeError.invalidHandshake
        }
    }

    private static func validateBundledHelperSignature(at executableURL: URL) throws {
        let codeURL = enclosingAppBundle(for: executableURL) ?? executableURL
        let helperCode = try staticCode(at: codeURL)
        let hostCode = try staticCode(at: Bundle.main.bundleURL)
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures |
                kSecCSCheckNestedCode |
                kSecCSStrictValidate |
                kSecCSRestrictSymlinks
        )
        let status = SecStaticCodeCheckValidity(helperCode, flags, nil)
        guard status == errSecSuccess else {
            throw SidecarRuntimeError.invalidCodeSignature(status)
        }

        let hostStatus = SecStaticCodeCheckValidity(hostCode, flags, nil)
        guard hostStatus == errSecSuccess else {
            throw SidecarRuntimeError.invalidCodeSignature(hostStatus)
        }

        let helperTeam = try signingTeamIdentifier(for: helperCode)
        let hostTeam = try signingTeamIdentifier(for: hostCode)
        switch (helperTeam, hostTeam) {
        case let (helper?, host?) where helper == host:
            break
        case (nil, nil):
            // A strict validation of the outer bundle above seals its nested helper.
            // This permits a local ad-hoc research build without weakening a
            // Developer-ID build, whose non-empty team identifiers must match.
            break
        default:
            throw SidecarRuntimeError.signingIdentityMismatch
        }
    }

    private static func enclosingAppBundle(for executableURL: URL) -> URL? {
        let marker = "/Contents/MacOS/"
        guard let range = executableURL.path.range(of: marker, options: .backwards) else {
            return nil
        }
        return URL(filePath: String(executableURL.path[..<range.lowerBound]), directoryHint: .isDirectory)
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else {
            throw SidecarRuntimeError.invalidCodeSignature(status)
        }
        return code
    }

    private static func signingTeamIdentifier(for code: SecStaticCode) throws -> String? {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard status == errSecSuccess else {
            throw SidecarRuntimeError.invalidCodeSignature(status)
        }
        let dictionary = information as? [String: Any]
        return dictionary?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func sanitizedEnvironment(from source: [String: String]) -> [String: String] {
        let allowed = ["PATH", "LANG", "LC_ALL", "TMPDIR"]
        return Dictionary(uniqueKeysWithValues: allowed.compactMap { key in
            source[key].map { (key, $0) }
        })
    }

    private func childEnvironment(for helper: ResolvedHelper) throws -> [String: String] {
        var child = Self.sanitizedEnvironment(from: environment)
        if helper.isBundled {
            guard let resources = Bundle.main.resourceURL else {
                throw SidecarRuntimeError.modelPackUnavailable
            }
            let pack = resources.appending(path: "PaceBackModelPack", directoryHint: .isDirectory)
            let trustKeyURL = resources.appending(
                path: "PaceBackModelTrustKey.b64",
                directoryHint: .notDirectory
            )
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: pack.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.fileExists(atPath: trustKeyURL.path),
                  let trustKey = try? String(contentsOf: trustKeyURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let decodedKey = Data(base64Encoded: trustKey),
                  decodedKey.count == 32 else {
                throw SidecarRuntimeError.modelPackUnavailable
            }
            child["PACEBACK_MODEL_PACK_DIR"] = pack.path
            child["PACEBACK_MODEL_TRUST_KEY"] = trustKey
            return child
        }

        #if DEBUG
        if let pack = environment["PACEBACK_MODEL_PACK_DIR"],
           let trustKey = environment["PACEBACK_MODEL_TRUST_KEY"] {
            child["PACEBACK_MODEL_PACK_DIR"] = pack
            child["PACEBACK_MODEL_TRUST_KEY"] = trustKey
        }
        #endif
        return child
    }

    private static func engineStorageDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = applicationSupport
            .appending(path: "PaceBack", directoryHint: .isDirectory)
            .appending(path: "Engine", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        return directory
    }

    nonisolated fileprivate static func randomSecret(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SidecarRuntimeError.randomGeneration(status)
        }
        return Data(bytes).base64EncodedString()
    }

    private static func readStartupLine(
        from handle: FileHandle,
        process: Process
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            var line = Data()
            while line.count <= 4_096 {
                guard let byte = try handle.read(upToCount: 1), !byte.isEmpty else {
                    throw SidecarRuntimeError.helperExited(process.terminationStatus)
                }
                if byte[byte.startIndex] == 0x0A { return line }
                line.append(byte)
            }
            throw SidecarRuntimeError.invalidHandshake
        }.value
    }
}

private struct SidecarHandshake: Decodable {
    let protocolVersion: String
    let pid: Int32
    let port: Int
    let ready: Bool
}

private struct EngineStorageKeyStore {
    private let service = "org.hackforhumanity.paceback.engine.release-v1"
    private let account = "sqlcipher-key-v1"

    func loadOrCreate() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let key = String(data: data, encoding: .utf8), key.utf8.count >= 32 {
            return key
        }
        guard status == errSecItemNotFound else {
            throw SidecarRuntimeError.keychain(status)
        }
        let key = try SidecarEngineRuntime.randomSecret()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8)
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SidecarRuntimeError.keychain(addStatus)
        }
        return key
    }
}

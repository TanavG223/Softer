import CryptoKit
import Foundation
import Testing
@testable import PaceBackiOS

@Suite("Deterministic safety gate")
struct SafetyGateTests {
    @Test("Young-child signs are age filtered")
    func youngChildSignsAreAgeFiltered() {
        let youngChildSigns = SafetyGate.signs(for: .youngChild0To5)
        let adultSigns = SafetyGate.signs(for: .adult18To64)

        #expect(youngChildSigns.contains(.inconsolableCrying))
        #expect(youngChildSigns.contains(.refusesToNurseOrEat))
        #expect(!adultSigns.contains(.inconsolableCrying))
        #expect(!adultSigns.contains(.refusesToNurseOrEat))
    }

    @Test("Any permitted selection produces static emergency instructions")
    func permittedSelectionProducesEmergency() {
        let result = SafetyGate.evaluate(
            selected: [.worseningHeadache],
            ageBand: .teen13To17
        )

        #expect(result.isEmergency)
        guard case .emergency(let signs, let instructions) = result else {
            Issue.record("Expected the deterministic emergency result")
            return
        }
        #expect(signs == [.worseningHeadache])
        #expect(instructions == SafetyGate.emergencyInstructions)
        #expect(instructions.contains("Call 911"))
        #expect(instructions.contains("Do not wait for an AI response"))
    }

    @Test("Wrong-age signs cannot trigger an adult result")
    func wrongAgeSignsAreIgnored() {
        let result = SafetyGate.evaluate(
            selected: [.inconsolableCrying],
            ageBand: .adult18To64
        )
        #expect(result == .clear)
    }
}

@Suite("Age and role permissions")
struct RolePolicyTests {
    @Test("Under-13 profiles are caregiver operated")
    func under13Roles() {
        #expect(RolePolicy.validRoles(for: .youngChild0To5) == [.guardian, .caregiver])
        #expect(RolePolicy.validRoles(for: .child6To12) == [.guardian, .caregiver])
        #expect(!RolePolicy.validRoles(for: .child6To12).contains(.selfManaged))
    }

    @Test("Teen administration stays guardian only")
    func teenAdministrativePermissions() {
        let teen = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .teenUser)
        let guardian = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .guardian)

        #expect(RolePolicy.permits(.useGuidedSessions, profile: teen))
        #expect(!RolePolicy.permits(.manageCarePlan, profile: teen))
        #expect(!RolePolicy.permits(.deleteProfile, profile: teen))
        #expect(RolePolicy.permits(.manageCarePlan, profile: guardian))
        #expect(RolePolicy.requiresAdministrativeGate(.manageCarePlan, profile: guardian))
    }

    @Test("Adult caregiver access requires explicit approval")
    func adultCaregiverRequiresApproval() {
        let unapproved = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .caregiver,
            caregiverApproved: false
        )
        let approved = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .caregiver,
            caregiverApproved: true
        )

        #expect(!RolePolicy.permits(.askEvidence, profile: unapproved))
        #expect(RolePolicy.permits(.askEvidence, profile: approved))
        #expect(!RolePolicy.permits(.manageCarePlan, profile: approved))
    }

    @Test("Creation roles enforce guardian-initialized teens and owner-initialized adults")
    func creationRoles() {
        #expect(RolePolicy.creationRoles(for: .teen13To17) == [.guardian])
        #expect(RolePolicy.creationRoles(for: .adult18To64) == [.selfManaged])
        #expect(RolePolicy.creationRoles(for: .olderAdult65Plus) == [.selfManaged])
    }

    @Test("Adult handoff requires explicit caregiver approval")
    func adultHandoffRequiresApproval() {
        let unapproved = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .selfManaged,
            caregiverApproved: false
        )
        let approved = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .selfManaged,
            caregiverApproved: true
        )

        #expect(
            RoleHandoffPolicy.decision(for: unapproved, switchingTo: .caregiver)
                == .denied(reason: "The profile owner must approve caregiver access first.")
        )
        #expect(
            RoleHandoffPolicy.decision(for: approved, switchingTo: .caregiver)
                == .allowed(requiresAuthentication: false)
        )
    }
}

@Suite("Fail-closed iOS evidence engine")
struct AIEngineTests {
    @Test("The iOS engine reports an explicit unavailable state")
    func unavailableState() async {
        let engine = OnDeviceUnavailableAIEngine()
        let availability = await engine.availability()
        #expect(availability.title == "Evidence engine unavailable on this iOS device")
        #expect(availability.detail.contains("have not been installed"))
        #expect(availability.detail.contains("no question leaves this device"))
    }

    @Test("No unverified answer or citation can be returned")
    func askFailsClosed() async {
        let engine = OnDeviceUnavailableAIEngine()
        let request = EvidenceRequest(
            question: "Can I return to sport?",
            profileID: UUID(),
            ageBand: .teen13To17,
            actingRole: .teenUser,
            careContext: .school
        )

        do {
            _ = try await engine.ask(request)
            Issue.record("The unavailable engine must never return an answer")
        } catch let error as AIEngineError {
            #expect(error == .onDeviceModelUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite("Encrypted per-profile persistence")
struct SecureProfileRepositoryTests {
    @Test("Profiles round trip without plaintext aliases")
    func encryptedRoundTrip() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = DeterministicKeyProvider()
        let repository = SecureProfileRepository(rootURL: root, keyProvider: keys)
        let first = LocalProfile(alias: "PrivateAliasOne", ageBand: .child6To12, actingRole: .guardian)
        let second = LocalProfile(alias: "PrivateAliasTwo", ageBand: .olderAdult65Plus, actingRole: .selfManaged)

        try await repository.saveProfiles([first, second])
        let loaded = try await repository.loadProfiles()

        #expect(loaded == [first, second])
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(files.count == 3)
        for file in files {
            let encrypted = try Data(contentsOf: file)
            #expect(encrypted.range(of: Data(first.alias.utf8)) == nil)
            #expect(encrypted.range(of: Data(second.alias.utf8)) == nil)
        }

        let namespaces = await keys.requestedNamespaces()
        #expect(namespaces.contains("profile.\(first.id.uuidString.lowercased())"))
        #expect(namespaces.contains("profile.\(second.id.uuidString.lowercased())"))
        #expect(namespaces.contains("profile-index-v1"))
    }

    @Test("Authentication failure from tampering fails closed")
    func corruptionFailsClosed() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = SecureProfileRepository(
            rootURL: root,
            keyProvider: DeterministicKeyProvider()
        )
        let profile = LocalProfile(alias: "TamperTarget", ageBand: .adult18To64, actingRole: .selfManaged)
        try await repository.saveProfiles([profile])

        let profileURL = root.appending(path: "\(profile.id.uuidString.lowercased()).pbe")
        var bytes = try Data(contentsOf: profileURL)
        bytes[bytes.startIndex] ^= 0xFF
        try bytes.write(to: profileURL, options: .atomic)

        do {
            _ = try await repository.loadProfiles()
            Issue.record("Tampered ciphertext must never load")
        } catch let error as ProfileRepositoryError {
            #expect(error == .corruptEncryptedStore)
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "paceback-ios-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

@Suite("Pediatric creation authentication")
@MainActor
struct AppStoreAuthenticationTests {
    @Test("Debug launch argument creates only an in-memory demo profile")
    func debugSyntheticProfile() async {
        let store = AppStore(
            launchArguments: ["PaceBack", "-PaceBackSyntheticProfile"]
        )
        await store.load()

        #expect(store.loadingState == .ready)
        #expect(store.profiles.count == 1)
        #expect(store.selectedProfile?.alias == "Demo")
        #expect(store.selectedProfile?.ageBand == .adult18To64)
    }

    @Test("Denied authentication prevents pediatric profile creation")
    func deniedPediatricCreation() async throws {
        let repository = InMemoryProfileRepository()
        let authenticator = RecordingAuthenticator(allowed: false)
        let store = AppStore(
            repository: repository,
            aiEngine: OnDeviceUnavailableAIEngine(),
            guardianAuthenticator: authenticator
        )

        let created = await store.createProfile(
            alias: "ChildAlias",
            ageBand: .child6To12,
            actingRole: .guardian
        )

        #expect(!created)
        #expect(store.profiles.isEmpty)
        #expect(try await repository.loadProfiles().isEmpty)
        #expect(await authenticator.callCount() == 1)
    }

    @Test("Guardian-initialized teen creation authenticates")
    func guardianInitializedTeenAuthenticates() async throws {
        let repository = InMemoryProfileRepository()
        let authenticator = RecordingAuthenticator(allowed: true)
        let store = AppStore(
            repository: repository,
            aiEngine: OnDeviceUnavailableAIEngine(),
            guardianAuthenticator: authenticator
        )

        let created = await store.createProfile(
            alias: "TeenAlias",
            ageBand: .teen13To17,
            actingRole: .guardian
        )

        #expect(created)
        #expect(store.profiles.count == 1)
        #expect(await authenticator.callCount() == 1)
    }

    @Test("Adult self-managed creation does not invoke guardian auth")
    func adultCreationDoesNotAuthenticate() async {
        let authenticator = RecordingAuthenticator(allowed: false)
        let store = AppStore(
            repository: InMemoryProfileRepository(),
            aiEngine: OnDeviceUnavailableAIEngine(),
            guardianAuthenticator: authenticator
        )

        let created = await store.createProfile(
            alias: "AdultAlias",
            ageBand: .adult18To64,
            actingRole: .selfManaged
        )

        #expect(created)
        #expect(await authenticator.callCount() == 0)
    }

    @Test("Approved adult caregiver handoff is revocable and owner return authenticates")
    func adultCaregiverHandoff() async {
        let authenticator = RecordingAuthenticator(allowed: true)
        let store = AppStore(
            repository: InMemoryProfileRepository(),
            aiEngine: OnDeviceUnavailableAIEngine(),
            guardianAuthenticator: authenticator
        )
        #expect(
            await store.createProfile(
                alias: "Owner",
                ageBand: .adult18To64,
                actingRole: .selfManaged
            )
        )
        #expect(await store.setCaregiverApproval(true))
        #expect(await store.switchRole(to: .caregiver))
        #expect(store.selectedProfile?.actingRole == .caregiver)
        #expect(await authenticator.callCount() == 0)
        #expect(await store.switchRole(to: .selfManaged))
        #expect(store.selectedProfile?.actingRole == .selfManaged)
        #expect(await authenticator.callCount() == 1)
    }
}

@Suite("Pinned iOS model pack trust and transport")
struct ModelPackTrustTests {
    @Test("Production manifest has the exact immutable four-artifact contract")
    func productionManifestContract() throws {
        #expect(PaceBackModelPack.artifacts.count == 4)
        #expect(PaceBackModelPack.artifacts.reduce(0) { $0 + $1.sizeBytes } == 157_716_998)
        #expect(PaceBackModelPack.totalSizeBytes == 157_716_998)
        #expect(PaceBackModelPack.minimumFreeSpaceBytes == 357_919_352)
        #expect(PaceBackModelPack.artifacts.allSatisfy { ModelPackDownloader.isApprovedSourceURL($0.sourceURL) })
        #expect(PaceBackModelPack.artifacts.allSatisfy { $0.sourceURL.absoluteString.contains("/resolve/") })
        #expect(PaceBackModelPack.artifacts.allSatisfy { artifact in
            artifact.sourceURL.absoluteString.contains(PaceBackModelPack.denseRevision)
                || artifact.sourceURL.absoluteString.contains(PaceBackModelPack.rerankerRevision)
        })

        let material = try BundledModelPackTrustMaterialProvider().loadTrustMaterial()
        try ModelPackTrustValidator().validateTrustMaterial(material)
    }

    @Test("Signed manifest tampering fails closed")
    func signedManifestTamperingFailsClosed() throws {
        let material = try BundledModelPackTrustMaterialProvider().loadTrustMaterial()
        var object = try #require(
            JSONSerialization.jsonObject(with: material.manifestData) as? [String: Any]
        )
        object["packID"] = "attacker-pack"
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        do {
            try ModelPackTrustValidator().validateTrustMaterial(
                ModelPackTrustMaterial(
                    manifestData: tampered,
                    publicKeyData: material.publicKeyData
                )
            )
            Issue.record("A changed signed manifest must be rejected")
        } catch let failure as ModelPackFailure {
            #expect(failure == .invalidManifestSignature)
        } catch {
            Issue.record("Unexpected trust-validation error: \(error)")
        }
    }

    @Test("Transport accepts only HTTPS Hugging Face and approved CDN hosts")
    func hostAndSchemeAllowlist() {
        #expect(ModelPackDownloader.isApprovedNetworkURL(URL(string: "https://huggingface.co/a")!))
        #expect(ModelPackDownloader.isApprovedNetworkURL(URL(string: "https://us.aws.cdn.hf.co/a")!))
        #expect(!ModelPackDownloader.isApprovedNetworkURL(URL(string: "http://huggingface.co/a")!))
        #expect(!ModelPackDownloader.isApprovedNetworkURL(URL(string: "https://huggingface.co.evil.example/a")!))
        #expect(!ModelPackDownloader.isApprovedNetworkURL(URL(string: "https://evil-hf.co/a")!))
        #expect(!ModelPackDownloader.isApprovedSourceURL(URL(string: "https://us.aws.cdn.hf.co/a")!))
    }

    @Test("Model request is ephemeral and contains no profile payload")
    func requestPrivacyAndNetworkConsent() {
        let artifact = PaceBackModelPack.artifacts[0]
        let request = ModelPackDownloader.request(for: artifact)
        #expect(request.url == artifact.sourceURL)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpShouldHandleCookies == false)

        let wifi = ModelPackDownloader.ephemeralConfiguration(for: .wifiOnly)
        #expect(wifi.urlCache == nil)
        #expect(wifi.httpCookieStorage == nil)
        #expect(wifi.httpShouldSetCookies == false)
        #expect(wifi.allowsCellularAccess == false)

        let cellular = ModelPackDownloader.ephemeralConfiguration(for: .wifiAndCellular)
        #expect(cellular.allowsCellularAccess)
        #expect(cellular.allowsExpensiveNetworkAccess)
    }

    @Test("Free-space preflight passes at the exact boundary and fails one byte below")
    func freeSpaceBoundary() async {
        let exactRoot = temporaryModelRoot()
        let lowRoot = temporaryModelRoot()
        defer {
            try? FileManager.default.removeItem(at: exactRoot)
            try? FileManager.default.removeItem(at: lowRoot)
        }
        let exactStore = ModelPackStore(
            rootURL: exactRoot,
            capacityProvider: FixedCapacityProvider(bytes: PaceBackModelPack.minimumFreeSpaceBytes)
        )
        let lowStore = ModelPackStore(
            rootURL: lowRoot,
            capacityProvider: FixedCapacityProvider(bytes: PaceBackModelPack.minimumFreeSpaceBytes - 1)
        )

        let exact = await exactStore.preflight()
        let low = await lowStore.preflight()
        do {
            let capacity = try exact.get()
            #expect(capacity == ModelPackCapacity(
                availableBytes: PaceBackModelPack.minimumFreeSpaceBytes,
                requiredBytes: PaceBackModelPack.minimumFreeSpaceBytes
            ))
        } catch {
            Issue.record("The exact working-space boundary should pass: \(error)")
        }
        do {
            _ = try low.get()
            Issue.record("One byte below the working-space boundary must fail")
        } catch {
            #expect(
                error == .insufficientSpace(
                    required: PaceBackModelPack.minimumFreeSpaceBytes,
                    available: PaceBackModelPack.minimumFreeSpaceBytes - 1
                )
            )
        }
    }
}

@Suite("Model pack staging and activation")
struct ModelPackStoreTests {
    @Test("Only a signed, hash-matched staging pack activates")
    func stagedActivationAndDeletion() async throws {
        let fixture = try TestModelPackFixture()
        let root = temporaryModelRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ModelStatusRecorder()
        let store = fixture.makeStore(root: root)

        let status = await store.install(networkPolicy: .wifiOnly) { state in
            await recorder.append(state)
        }
        guard case .ready(let receipt) = status else {
            Issue.record("Expected a ready model pack, got \(status)")
            return
        }
        #expect(receipt.installedBytes == fixture.descriptor.totalSizeBytes)
        #expect(
            try store.installedRootURL().standardizedFileURL.path()
                == root.appending(path: "active").standardizedFileURL.path()
        )
        #expect(FileManager.default.fileExists(atPath: receipt.rootURL.appending(path: "manifest.json").path()))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "staging").path()))

        for artifact in fixture.descriptor.artifacts {
            let fileURL = receipt.rootURL.appending(path: artifact.relativePath)
            #expect(try Data(contentsOf: fileURL) == fixture.payloads[artifact.id])
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path())
            let protection = attributes[.protectionKey] as? FileProtectionType
            #if targetEnvironment(simulator)
            // The simulator's host filesystem can accept the protection attribute while
            // omitting it from a later stat. A present value must still be the pinned policy.
            if let protection {
                #expect(protection == .completeUntilFirstUserAuthentication)
            }
            #else
            #expect(protection == .completeUntilFirstUserAuthentication)
            #endif
        }

        let states = await recorder.values()
        #expect(states.contains { if case .downloading = $0 { true } else { false } })
        #expect(states.contains { if case .verifying = $0 { true } else { false } })
        #expect(states.last == status)

        #expect(await store.deleteInstallation() == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: receipt.rootURL.path()))
        #expect(throws: ModelPackFailure.self) { try store.installedRootURL() }
    }

    @Test("A hash failure never replaces a previously active pack")
    func failedReinstallPreservesActivePack() async throws {
        let fixture = try TestModelPackFixture()
        let root = temporaryModelRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FixtureModelDownloader(payloads: fixture.payloads)
        let store = fixture.makeStore(root: root, downloader: downloader)

        let first = await store.install(networkPolicy: .wifiOnly) { _ in }
        guard case .ready(let receipt) = first else {
            Issue.record("Initial pack did not activate")
            return
        }
        let originalDense = try Data(contentsOf: receipt.rootURL.appending(path: "dense/model.onnx"))

        downloader.corruptArtifact("dense-model")
        let reinstall = await store.install(networkPolicy: .wifiOnly, force: true) { _ in }
        guard case .failed(let failure) = reinstall else {
            Issue.record("Corrupted reinstall unexpectedly activated")
            return
        }
        #expect(failure == .hashMismatch(artifact: "Test meaning weights"))
        #expect(try store.installedRootURL() == receipt.rootURL)
        #expect(try Data(contentsOf: receipt.rootURL.appending(path: "dense/model.onnx")) == originalDense)
    }

    @Test("Interrupted staging is paused and a retry completes without activation leakage")
    func interruptedRetry() async throws {
        let fixture = try TestModelPackFixture()
        let root = temporaryModelRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FixtureModelDownloader(payloads: fixture.payloads)
        downloader.cancelArtifact("dense-tokenizer")
        let store = fixture.makeStore(root: root, downloader: downloader)

        let paused = await store.install(networkPolicy: .wifiOnly) { _ in }
        guard case .paused(let progress) = paused else {
            Issue.record("Expected a safe paused state")
            return
        }
        #expect(progress.receivedBytes == Int64(fixture.payloads["dense-model"]?.count ?? 0))
        #expect(throws: ModelPackFailure.self) { try store.installedRootURL() }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "active").path()))

        downloader.resumeAll()
        let ready = await store.install(networkPolicy: .wifiOnly) { _ in }
        #expect(ready.isReady)
        #expect(downloader.downloadCount(for: "dense-model") == 1)
    }
}

private actor DeterministicKeyProvider: ProfileKeyProvider {
    private var namespaces: Set<String> = []

    func key(for namespace: String) async throws -> SymmetricKey {
        namespaces.insert(namespace)
        let digest = SHA256.hash(data: Data("paceback-test-key:\(namespace)".utf8))
        return SymmetricKey(data: Data(digest))
    }

    func deleteKey(for namespace: String) async throws {
        namespaces.remove(namespace)
    }

    func requestedNamespaces() -> Set<String> { namespaces }
}

private actor RecordingAuthenticator: GuardianAuthenticator {
    private let allowed: Bool
    private var calls = 0

    init(allowed: Bool) {
        self.allowed = allowed
    }

    func authenticate(reason: String) async -> Bool {
        _ = reason
        calls += 1
        return allowed
    }

    func callCount() -> Int { calls }
}

private struct FixedCapacityProvider: ModelPackDiskCapacityProviding {
    let bytes: Int64

    func availableCapacity(at url: URL) throws -> Int64 {
        _ = url
        return bytes
    }
}

private actor ModelStatusRecorder {
    private var statuses: [ModelPackStatus] = []

    func append(_ status: ModelPackStatus) {
        statuses.append(status)
    }

    func values() -> [ModelPackStatus] { statuses }
}

private final class FixtureModelDownloader: ModelPackDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private let payloads: [String: Data]
    private var corruptIDs: Set<String> = []
    private var cancellationIDs: Set<String> = []
    private var counts: [String: Int] = [:]

    init(payloads: [String: Data]) {
        self.payloads = payloads
    }

    func download(
        _ artifact: ModelPackArtifact,
        to destinationURL: URL,
        resumeDataURL: URL,
        networkPolicy: ModelPackNetworkPolicy,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        _ = resumeDataURL
        _ = networkPolicy
        let action = withLock { () -> (Data?, Bool, Bool) in
            counts[artifact.id, default: 0] += 1
            return (
                payloads[artifact.id],
                corruptIDs.contains(artifact.id),
                cancellationIDs.contains(artifact.id)
            )
        }
        guard var payload = action.0 else {
            throw ModelPackFailure.downloadFailed(
                artifact: artifact.displayName,
                reason: "Missing fixture bytes"
            )
        }
        if action.2 {
            await progress(0)
            throw CancellationError()
        }
        if action.1, !payload.isEmpty {
            payload[payload.startIndex] ^= 0xFF
        }
        await progress(Int64(payload.count / 2))
        try payload.write(to: destinationURL, options: [.atomic])
        await progress(Int64(payload.count))
    }

    func cancel() {}

    func corruptArtifact(_ id: String) {
        withLock { corruptIDs.insert(id) }
    }

    func cancelArtifact(_ id: String) {
        withLock { cancellationIDs.insert(id) }
    }

    func resumeAll() {
        withLock { cancellationIDs.removeAll() }
    }

    func downloadCount(for id: String) -> Int {
        withLock { counts[id, default: 0] }
    }

    @discardableResult
    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private struct TestModelPackFixture {
    let payloads: [String: Data]
    let descriptor: ModelPackDescriptor
    let material: ModelPackTrustMaterial

    init() throws {
        let payloads = [
            "dense-model": Data("test-dense-weights-v1".utf8),
            "dense-tokenizer": Data("test-dense-tokenizer-v1".utf8),
            "reranker-model": Data("test-reranker-weights-v1".utf8),
            "reranker-tokenizer": Data("test-reranker-tokenizer-v1".utf8),
        ]
        let specs: [(String, String, String)] = [
            ("dense-model", "Test meaning weights", "dense/model.onnx"),
            ("dense-tokenizer", "Test meaning tokenizer", "dense/tokenizer.json"),
            ("reranker-model", "Test reranker weights", "reranker/model.onnx"),
            ("reranker-tokenizer", "Test reranker tokenizer", "reranker/tokenizer.json"),
        ]
        let artifacts = specs.map { id, name, path -> ModelPackArtifact in
            let data = payloads[id]!
            return ModelPackArtifact(
                id: id,
                displayName: name,
                relativePath: path,
                sourceURL: URL(string: "https://huggingface.co/paceback/test/resolve/0123456789012345678901234567890123456789/\(path)")!,
                sha256: sha256Hex(data),
                sizeBytes: Int64(data.count)
            )
        }
        let total = artifacts.reduce(0) { $0 + $1.sizeBytes }
        let descriptor = ModelPackDescriptor(
            packID: "paceback-test-pack-v1",
            formatVersion: 1,
            denseModelID: "paceback/test-dense",
            denseRevision: "0123456789012345678901234567890123456789",
            rerankerModelID: "paceback/test-reranker",
            rerankerRevision: "9876543210987654321098765432109876543210",
            artifacts: artifacts,
            totalSizeBytes: total,
            minimumFreeSpaceBytes: total
        )

        let denseModel = artifacts.first { $0.id == "dense-model" }!
        let denseTokenizer = artifacts.first { $0.id == "dense-tokenizer" }!
        let rerankerModel = artifacts.first { $0.id == "reranker-model" }!
        let rerankerTokenizer = artifacts.first { $0.id == "reranker-tokenizer" }!
        let unsigned: [String: Any] = [
            "formatVersion": descriptor.formatVersion,
            "packID": descriptor.packID,
            "createdAt": "2026-08-26T00:00:00Z",
            "components": [
                "dense": [
                    "modelID": descriptor.denseModelID,
                    "revision": descriptor.denseRevision,
                    "model": Self.artifactObject(denseModel),
                    "tokenizer": Self.artifactObject(denseTokenizer),
                ],
                "reranker": [
                    "modelID": descriptor.rerankerModelID,
                    "revision": descriptor.rerankerRevision,
                    "model": Self.artifactObject(rerankerModel),
                    "tokenizer": Self.artifactObject(rerankerTokenizer),
                ],
            ],
        ]
        let canonical = try JSONSerialization.data(
            withJSONObject: unsigned,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(for: canonical)
        var signed = unsigned
        signed["signature"] = [
            "algorithm": "ed25519",
            "value": signature.base64EncodedString(),
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: signed,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        self.payloads = payloads
        self.descriptor = descriptor
        material = ModelPackTrustMaterial(
            manifestData: manifestData,
            publicKeyData: privateKey.publicKey.rawRepresentation
        )
    }

    func makeStore(
        root: URL,
        downloader: FixtureModelDownloader? = nil
    ) -> ModelPackStore {
        ModelPackStore(
            rootURL: root,
            downloader: downloader ?? FixtureModelDownloader(payloads: payloads),
            capacityProvider: FixedCapacityProvider(bytes: descriptor.minimumFreeSpaceBytes),
            trustProvider: FixedModelPackTrustMaterialProvider(material: material),
            descriptor: descriptor
        )
    }

    private static func artifactObject(_ artifact: ModelPackArtifact) -> [String: Any] {
        [
            "path": artifact.relativePath,
            "sha256": artifact.sha256,
            "sizeBytes": artifact.sizeBytes,
        ]
    }
}

private func temporaryModelRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "paceback-model-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

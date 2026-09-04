import CryptoKit
import Darwin
import Foundation
import Security

public protocol ProfileRepository: Sendable {
    func loadProfiles() async throws -> [LocalProfile]
    func saveProfiles(_ profiles: [LocalProfile]) async throws
    func deleteProfile(id: UUID) async throws -> ProfileDeletionOutcome
}

public enum ProfileDeletionOutcome: Equatable, Sendable {
    case deleted
    case deletedWithResiduals([String])
}

public enum ProfileRepositoryError: LocalizedError, Equatable, Sendable {
    case keychain(OSStatus)
    case corruptVault
    case missingProfileFile(UUID)
    case cleanupFailed([String])

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "The macOS Keychain could not provide an encryption key (status \(status))."
        case .corruptVault:
            return "The encrypted profile workspace could not be verified. No partial data was loaded."
        case .missingProfileFile:
            return "An encrypted profile file is missing. No partial data was loaded."
        case .cleanupFailed(let details):
            let joined = details.joined(separator: "; ")
            return "The profile change was saved, but encrypted residual cleanup could not be verified: \(joined)"
        }
    }
}

protocol ProfileKeyProviding: Sendable {
    // Data is Sendable on every supported SDK. Keeping CryptoKit's
    // SymmetricKey inside the consuming actor avoids crossing an actor
    // boundary with the older macOS 14 CryptoKit declaration, where the type
    // was not yet annotated Sendable.
    func existingKeyData(for account: String) async throws -> Data
    func keyData(for account: String) async throws -> Data
    func deleteKey(for account: String) async throws
}

actor KeychainProfileKeyProvider: ProfileKeyProviding {
    private let service: String

    init(service: String = "org.hackforhumanity.paceback") {
        self.service = service
    }

    func existingKeyData(for account: String) async throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw ProfileRepositoryError.keychain(status)
        }
        return data
    }

    func keyData(for account: String) async throws -> Data {
        do {
            return try await existingKeyData(for: account)
        } catch ProfileRepositoryError.keychain(let status) where status == errSecItemNotFound {
            let generated = SymmetricKey(size: .bits256)
            let data = generated.withUnsafeBytes { Data($0) }
            var add = baseQuery(account: account)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                return try await existingKeyData(for: account)
            }
            guard addStatus == errSecSuccess else {
                throw ProfileRepositoryError.keychain(addStatus)
            }
            return data
        }
    }

    func deleteKey(for account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProfileRepositoryError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

/// A local encrypted repository with an authenticated index as its sole commit
/// pointer. Profile updates are written to immutable generation files before
/// the index is atomically replaced, so an interrupted save exposes either the
/// complete old state or the complete new state, never a mixture.
public actor EncryptedProfileRepository: ProfileRepository {
    private struct ProfileReference: Codable, Hashable, Sendable {
        let id: UUID
        let ciphertextFileName: String
    }

    private struct ProfileIndex: Codable, Sendable {
        static let currentSchemaVersion = 2
        let schemaVersion: Int
        let profiles: [ProfileReference]
    }

    private struct LegacyProfileIndex: Codable, Sendable {
        let profileIDs: [UUID]
    }

    private let directory: URL
    private let keyProvider: any ProfileKeyProviding
    private let fileManager: SendableFileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var transactionIsActive = false
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        directory: URL? = nil,
        keychainService: String = "org.hackforhumanity.paceback",
        fileManager: FileManager = .default
    ) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        // Keep the legacy on-disk directory so a display-name change cannot strand
        // an existing encrypted profile or silently create an empty workspace.
        self.directory = directory ?? appSupport.appending(path: "PaceBack", directoryHint: .isDirectory)
        self.keyProvider = KeychainProfileKeyProvider(service: keychainService)
        self.fileManager = SendableFileManager(fileManager)
    }

    init(
        directory: URL,
        keyProvider: any ProfileKeyProviding,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.keyProvider = keyProvider
        self.fileManager = SendableFileManager(fileManager)
    }

    public func loadProfiles() async throws -> [LocalProfile] {
        await beginTransaction()
        defer { endTransaction() }

        let references = try await loadIndex()
        var profiles: [LocalProfile] = []
        profiles.reserveCapacity(references.count)

        for reference in references {
            let url = try profileURL(reference)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ProfileRepositoryError.missingProfileFile(reference.id)
            }
            let sealed = try Data(contentsOf: url)
            let keyData = try await keyProvider.existingKeyData(for: profileAccount(reference.id))
            let key = SymmetricKey(data: keyData)
            let clear = try Self.decrypt(sealed, with: key)
            let profile: LocalProfile
            do {
                profile = try decoder.decode(LocalProfile.self, from: clear)
            } catch {
                throw ProfileRepositoryError.corruptVault
            }
            guard profile.id == reference.id, Self.isValid(profile) else {
                throw ProfileRepositoryError.corruptVault
            }
            profiles.append(profile)
        }

        try await reconcileUnreferencedCiphertext(activeReferences: references)
        return profiles.sorted { $0.createdAt < $1.createdAt }
    }

    public func saveProfiles(_ profiles: [LocalProfile]) async throws {
        await beginTransaction()
        defer { endTransaction() }
        let warnings = try await saveProfilesTransaction(profiles)
        if !warnings.isEmpty { throw ProfileRepositoryError.cleanupFailed(warnings) }
    }

    public func deleteProfile(id: UUID) async throws -> ProfileDeletionOutcome {
        await beginTransaction()
        defer { endTransaction() }

        let references = try await loadIndex()
        guard references.contains(where: { $0.id == id }) else { return .deleted }

        var profiles: [LocalProfile] = []
        for reference in references where reference.id != id {
            let url = try profileURL(reference)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ProfileRepositoryError.missingProfileFile(reference.id)
            }
            let keyData = try await keyProvider.existingKeyData(for: profileAccount(reference.id))
            let key = SymmetricKey(data: keyData)
            let clear = try Self.decrypt(Data(contentsOf: url), with: key)
            guard let profile = try? decoder.decode(LocalProfile.self, from: clear),
                  profile.id == reference.id,
                  Self.isValid(profile) else {
                throw ProfileRepositoryError.corruptVault
            }
            profiles.append(profile)
        }

        let warnings = try await saveProfilesTransaction(profiles)
        return warnings.isEmpty ? .deleted : .deletedWithResiduals(warnings)
    }

    /// Must be called while the actor-wide transaction lock is held.
    private func saveProfilesTransaction(_ profiles: [LocalProfile]) async throws -> [String] {
        let oldReferences = try await loadIndex()
        guard Set(profiles.map(\.id)).count == profiles.count,
              profiles.allSatisfy(Self.isValid) else {
            throw ProfileRepositoryError.corruptVault
        }

        try ensureDirectory()
        let oldIDs = Set(oldReferences.map(\.id))
        let newIDs = Set(profiles.map(\.id))
        var stagedReferences: [ProfileReference] = []
        var stagedURLs: [URL] = []
        var pendingIndexURL: URL?

        do {
            for profile in profiles {
                let reference = ProfileReference(
                    id: profile.id,
                    ciphertextFileName: Self.generationFileName(for: profile.id)
                )
                let destination = try profileURL(reference)
                let keyData = try await keyProvider.keyData(for: profileAccount(profile.id))
                let key = SymmetricKey(data: keyData)
                let clear = try encoder.encode(profile)
                try Self.encrypt(clear, with: key).write(to: destination, options: .atomic)
                try setPrivatePermissions(destination)

                let verification = try Self.decrypt(Data(contentsOf: destination), with: key)
                guard try decoder.decode(LocalProfile.self, from: verification) == profile else {
                    throw ProfileRepositoryError.corruptVault
                }
                stagedReferences.append(reference)
                stagedURLs.append(destination)
            }

            let index = ProfileIndex(
                schemaVersion: ProfileIndex.currentSchemaVersion,
                profiles: stagedReferences
            )
            let keyData = try await keyProvider.keyData(for: indexAccount)
            let key = SymmetricKey(data: keyData)
            let pending = directory.appending(path: "index-\(UUID().uuidString.lowercased()).pending")
            pendingIndexURL = pending
            try Self.encrypt(try encoder.encode(index), with: key).write(to: pending, options: .atomic)
            try setPrivatePermissions(pending)
            try Self.atomicReplace(source: pending, destination: indexURL)
            pendingIndexURL = nil
        } catch {
            for url in stagedURLs { try? fileManager.removeItem(at: url) }
            if let pendingIndexURL { try? fileManager.removeItem(at: pendingIndexURL) }
            for newID in newIDs.subtracting(oldIDs) {
                try? await keyProvider.deleteKey(for: profileAccount(newID))
            }
            throw error
        }

        // Generations still required by the committed index are never touched.
        let activeFileNames = Set(stagedReferences.map(\.ciphertextFileName))
        for reference in oldReferences where newIDs.contains(reference.id)
            && !activeFileNames.contains(reference.ciphertextFileName) {
            if let url = try? profileURL(reference) { try? fileManager.removeItem(at: url) }
        }

        var warnings: [String] = []
        for removedID in oldIDs.subtracting(newIDs).sorted(by: { $0.uuidString < $1.uuidString }) {
            let urls = (try? allCiphertextURLs(for: removedID)) ?? []
            do {
                // Key destruction comes first. If it fails, preserve ciphertext
                // so a correctly entitled future build can retry safely.
                try await keyProvider.deleteKey(for: profileAccount(removedID))
            } catch {
                if !urls.isEmpty { warnings.append("\(removedID.uuidString): Keychain key was not destroyed") }
                continue
            }
            for url in urls {
                do { try fileManager.removeItem(at: url) }
                catch { warnings.append("\(removedID.uuidString): \(error.localizedDescription)") }
            }
        }
        return warnings
    }

    private func loadIndex() async throws -> [ProfileReference] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            if try containsCiphertextWithoutIndex() { throw ProfileRepositoryError.corruptVault }
            return []
        }

        do {
            let keyData = try await keyProvider.existingKeyData(for: indexAccount)
            let key = SymmetricKey(data: keyData)
            let clear = try Self.decrypt(Data(contentsOf: indexURL), with: key)

            if let current = try? decoder.decode(ProfileIndex.self, from: clear) {
                guard current.schemaVersion == ProfileIndex.currentSchemaVersion else {
                    throw ProfileRepositoryError.corruptVault
                }
                try validate(current.profiles, allowsLegacyNames: false)
                return current.profiles
            }

            if let legacy = try? decoder.decode(LegacyProfileIndex.self, from: clear) {
                let references = legacy.profileIDs.map {
                    ProfileReference(id: $0, ciphertextFileName: Self.legacyFileName(for: $0))
                }
                try validate(references, allowsLegacyNames: true)
                return references
            }
            throw ProfileRepositoryError.corruptVault
        } catch let error as ProfileRepositoryError {
            throw error
        } catch {
            throw ProfileRepositoryError.corruptVault
        }
    }

    private func reconcileUnreferencedCiphertext(activeReferences: [ProfileReference]) async throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let activeIDs = Set(activeReferences.map(\.id))
        let activeNames = Set(activeReferences.map(\.ciphertextFileName))
        let inventory = try ciphertextInventory()

        for item in inventory where activeIDs.contains(item.id) && !activeNames.contains(item.url.lastPathComponent) {
            try? fileManager.removeItem(at: item.url)
        }

        let orphanGroups = Dictionary(grouping: inventory.filter { !activeIDs.contains($0.id) }, by: \.id)
        for id in orphanGroups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                try await keyProvider.deleteKey(for: profileAccount(id))
            } catch {
                throw error
            }
            for item in orphanGroups[id] ?? [] { try? fileManager.removeItem(at: item.url) }
        }

        // Pending index files can never be the commit pointer.
        for candidate in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where candidate.lastPathComponent.hasPrefix("index-") && candidate.pathExtension == "pending" {
            try? fileManager.removeItem(at: candidate)
        }
    }

    private func ciphertextInventory() throws -> [(id: UUID, url: URL)] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).compactMap { candidate in
            guard candidate.pathExtension == "pbvault", candidate.lastPathComponent != indexURL.lastPathComponent else {
                return nil
            }
            guard let id = Self.profileID(from: candidate.lastPathComponent) else {
                throw ProfileRepositoryError.corruptVault
            }
            try validateCandidate(candidate)
            return (id, candidate)
        }
    }

    private func allCiphertextURLs(for id: UUID) throws -> [URL] {
        try ciphertextInventory().filter { $0.id == id }.map(\.url)
    }

    private func containsCiphertextWithoutIndex() throws -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .contains { $0.pathExtension == "pbvault" && $0.lastPathComponent != indexURL.lastPathComponent }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private var indexURL: URL { directory.appending(path: "index.pbvault") }
    private var indexAccount: String { "index" }
    private func profileAccount(_ id: UUID) -> String { "profile.\(id.uuidString)" }

    private func profileURL(_ reference: ProfileReference) throws -> URL {
        let url = directory.appending(path: reference.ciphertextFileName)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw ProfileRepositoryError.corruptVault
        }
        return url
    }

    private func validate(_ references: [ProfileReference], allowsLegacyNames: Bool) throws {
        guard Set(references.map(\.id)).count == references.count else {
            throw ProfileRepositoryError.corruptVault
        }
        for reference in references {
            let name = reference.ciphertextFileName
            guard name == URL(fileURLWithPath: name).lastPathComponent,
                  Self.isCanonical(name, for: reference.id, allowsLegacyName: allowsLegacyNames) else {
                throw ProfileRepositoryError.corruptVault
            }
        }
    }

    private func validateCandidate(_ candidate: URL) throws {
        guard candidate.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw ProfileRepositoryError.corruptVault
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true || values.isSymbolicLink == true else {
            throw ProfileRepositoryError.corruptVault
        }
    }

    private static func isValid(_ profile: LocalProfile) -> Bool {
        let canonicalAlias = String(profile.alias.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !canonicalAlias.isEmpty,
              canonicalAlias == profile.alias,
              RolePolicy.validRoles(for: profile.ageBand).contains(profile.actingRole) else { return false }
        if !profile.ageBand.isUnder13,
           profile.actingRole == .caregiver,
           !profile.caregiverApproved { return false }
        if let state = profile.wellbeing, !state.belongs(to: profile, at: .now) { return false }
        return true
    }

    private static func generationFileName(for id: UUID) -> String {
        "profile-\(id.uuidString.lowercased())-\(UUID().uuidString.lowercased()).pbvault"
    }

    private static func legacyFileName(for id: UUID) -> String { "\(id.uuidString).pbvault" }

    private static func isCanonical(_ name: String, for id: UUID, allowsLegacyName: Bool) -> Bool {
        if allowsLegacyName && name == legacyFileName(for: id) { return true }
        let prefix = "profile-\(id.uuidString.lowercased())-"
        guard name.hasPrefix(prefix), name.hasSuffix(".pbvault") else { return false }
        let token = name.dropFirst(prefix.count).dropLast(".pbvault".count)
        return UUID(uuidString: String(token))?.uuidString.lowercased() == String(token)
    }

    private static func profileID(from name: String) -> UUID? {
        if name.hasPrefix("profile-"), name.hasSuffix(".pbvault") {
            let body = name.dropFirst("profile-".count).dropLast(".pbvault".count)
            guard body.count == 73 else { return nil }
            let idText = String(body.prefix(36))
            let separator = body.index(body.startIndex, offsetBy: 36)
            let generationText = String(body.suffix(36))
            guard body[separator] == "-",
                  let id = UUID(uuidString: idText),
                  UUID(uuidString: generationText)?.uuidString.lowercased() == generationText,
                  id.uuidString.lowercased() == idText else { return nil }
            return id
        }
        guard name.hasSuffix(".pbvault") else { return nil }
        return UUID(uuidString: String(name.dropLast(".pbvault".count)))
    }

    private static func atomicReplace(source: URL, destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private static func encrypt(_ clear: Data, with key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(clear, using: key)
        guard let combined = sealed.combined else { throw ProfileRepositoryError.corruptVault }
        return combined
    }

    private static func decrypt(_ sealed: Data, with key: SymmetricKey) throws -> Data {
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key) }
        catch { throw ProfileRepositoryError.corruptVault }
    }

    private func beginTransaction() async {
        guard transactionIsActive else {
            transactionIsActive = true
            return
        }
        await withCheckedContinuation { transactionWaiters.append($0) }
    }

    private func endTransaction() {
        guard !transactionWaiters.isEmpty else {
            transactionIsActive = false
            return
        }
        transactionWaiters.removeFirst().resume()
    }
}

/// Tiny wrapper that keeps FileManager's non-Sendable reference behind the
/// repository actor while satisfying Swift 6 strict concurrency checks.
private struct SendableFileManager: @unchecked Sendable {
    private let value: FileManager
    init(_ value: FileManager) { self.value = value }
    func fileExists(atPath path: String) -> Bool { value.fileExists(atPath: path) }
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try value.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        try value.setAttributes(attributes, ofItemAtPath: path)
    }
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws -> [URL] {
        try value.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)
    }
    func removeItem(at url: URL) throws { try value.removeItem(at: url) }
}

public actor InMemoryProfileRepository: ProfileRepository {
    private var profiles: [LocalProfile]

    public init(profiles: [LocalProfile] = []) { self.profiles = profiles }
    public func loadProfiles() async throws -> [LocalProfile] { profiles }
    public func saveProfiles(_ profiles: [LocalProfile]) async throws { self.profiles = profiles }
    public func deleteProfile(id: UUID) async throws -> ProfileDeletionOutcome {
        profiles.removeAll { $0.id == id }
        return .deleted
    }
}

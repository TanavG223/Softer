import CryptoKit
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

public enum ProfileRepositoryError: LocalizedError, Sendable {
    case keychain(OSStatus)
    case corruptVault
    case cleanupFailed([String])

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "The local encryption key could not be accessed (\(status))."
        case .corruptVault: "The encrypted profile vault could not be read safely."
        case .cleanupFailed(let details):
            "The profile was removed from PaceBack, but encrypted residual cleanup could not be verified: \(details.joined(separator: "; "))"
        }
    }
}

private struct ProfileIndex: Codable, Sendable {
    var profileIDs: [UUID]
}

public actor EncryptedProfileRepository: ProfileRepository {
    private let directory: URL
    private let keychainService: String
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directory: URL? = nil,
        keychainService: String = "org.hackforhumanity.paceback",
        fileManager: FileManager = .default
    ) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory ?? appSupport.appending(path: "PaceBack", directoryHint: .isDirectory)
        self.keychainService = keychainService
        self.fileManager = fileManager
    }

    public func loadProfiles() async throws -> [LocalProfile] {
        let index = try loadIndex()
        return try index.profileIDs.map { id in
            let key = try key(for: "profile.\(id.uuidString)", createIfMissing: false)
            let data = try Data(contentsOf: profileURL(id))
            let clear = try decrypt(data, with: key)
            return try decoder.decode(LocalProfile.self, from: clear)
        }
    }

    public func saveProfiles(_ profiles: [LocalProfile]) async throws {
        try ensureDirectory()
        let existingIDs = Set(try loadIndex().profileIDs)
        let newIDs = Set(profiles.map(\.id))

        for profile in profiles {
            let key = try key(for: "profile.\(profile.id.uuidString)", createIfMissing: true)
            let clear = try encoder.encode(profile)
            try writeEncrypted(clear, with: key, to: profileURL(profile.id))
        }

        try saveIndex(ProfileIndex(profileIDs: profiles.map(\.id)))

        var cleanupFailures: [String] = []
        for removedID in existingIDs.subtracting(newIDs) {
            cleanupFailures.append(contentsOf: cleanupProfileArtifacts(id: removedID))
        }
        if !cleanupFailures.isEmpty {
            throw ProfileRepositoryError.cleanupFailed(cleanupFailures)
        }
    }

    public func deleteProfile(id: UUID) async throws -> ProfileDeletionOutcome {
        var index = try loadIndex()
        guard index.profileIDs.contains(id) else { return .deleted }

        // Remove the profile from the encrypted index before attempting
        // physical cleanup. This prevents an undecryptable orphan from being
        // presented as an active profile after a partial filesystem failure.
        index.profileIDs.removeAll { $0 == id }
        try saveIndex(index)

        let failures = cleanupProfileArtifacts(id: id)
        return failures.isEmpty ? .deleted : .deletedWithResiduals(failures)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private var indexURL: URL { directory.appending(path: "index.pbvault") }

    private func profileURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).pbvault")
    }

    private func loadIndex() throws -> ProfileIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return ProfileIndex(profileIDs: [])
        }
        do {
            let key = try key(for: "index", createIfMissing: false)
            let sealed = try Data(contentsOf: indexURL)
            return try decoder.decode(ProfileIndex.self, from: decrypt(sealed, with: key))
        } catch let error as ProfileRepositoryError {
            throw error
        } catch {
            throw ProfileRepositoryError.corruptVault
        }
    }

    private func saveIndex(_ index: ProfileIndex) throws {
        try ensureDirectory()
        let key = try key(for: "index", createIfMissing: true)
        try writeEncrypted(try encoder.encode(index), with: key, to: indexURL)
    }

    private func writeEncrypted(_ clear: Data, with key: SymmetricKey, to url: URL) throws {
        let sealed = try AES.GCM.seal(clear, using: key)
        guard let combined = sealed.combined else { throw ProfileRepositoryError.corruptVault }
        try combined.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func decrypt(_ sealed: Data, with key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
        } catch {
            throw ProfileRepositoryError.corruptVault
        }
    }

    private func key(for account: String, createIfMissing: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound, createIfMissing else {
            throw ProfileRepositoryError.keychain(status)
        }

        let generated = SymmetricKey(size: .bits256)
        let data = generated.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ProfileRepositoryError.keychain(addStatus) }
        return generated
    }

    private func deleteKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProfileRepositoryError.keychain(status)
        }
    }

    private func cleanupProfileArtifacts(id: UUID) -> [String] {
        var failures: [String] = []
        let url = profileURL(id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                failures.append("encrypted file: \(error.localizedDescription)")
            }
        }
        do {
            try deleteKey(account: "profile.\(id.uuidString)")
        } catch {
            failures.append("Keychain key: \(error.localizedDescription)")
        }
        return failures
    }
}

public actor InMemoryProfileRepository: ProfileRepository {
    private var profiles: [LocalProfile]

    public init(profiles: [LocalProfile] = []) {
        self.profiles = profiles
    }

    public func loadProfiles() async throws -> [LocalProfile] { profiles }

    public func saveProfiles(_ profiles: [LocalProfile]) async throws {
        self.profiles = profiles
    }

    public func deleteProfile(id: UUID) async throws -> ProfileDeletionOutcome {
        profiles.removeAll { $0.id == id }
        return .deleted
    }
}

import CryptoKit
import Foundation
import Security

enum ProfileRepositoryError: LocalizedError, Equatable, Sendable {
    case keychain(OSStatus)
    case corruptEncryptedStore
    case missingProfileFile(UUID)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "The iOS Keychain could not provide an encryption key (status \(status))."
        case .corruptEncryptedStore:
            "The encrypted profile store could not be verified. No partial data was loaded."
        case .missingProfileFile:
            "An encrypted profile file is missing. No partial data was loaded."
        }
    }
}

protocol ProfileRepository: Sendable {
    func loadProfiles() async throws -> [LocalProfile]
    func saveProfiles(_ profiles: [LocalProfile]) async throws
}

protocol ProfileKeyProvider: Sendable {
    func key(for namespace: String) async throws -> SymmetricKey
    func deleteKey(for namespace: String) async throws
}

actor KeychainProfileKeyProvider: ProfileKeyProvider {
    private let service: String

    init(service: String = "org.paceback.research.ios.profile-keys") {
        self.service = service
    }

    func key(for namespace: String) async throws -> SymmetricKey {
        var query = baseQuery(namespace: namespace)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw ProfileRepositoryError.keychain(status)
        }

        let newKey = SymmetricKey(size: .bits256)
        let data = newKey.withUnsafeBytes { Data($0) }
        var add = baseQuery(namespace: namespace)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)

        if addStatus == errSecDuplicateItem {
            return try await key(for: namespace)
        }
        guard addStatus == errSecSuccess else {
            throw ProfileRepositoryError.keychain(addStatus)
        }
        return newKey
    }

    func deleteKey(for namespace: String) async throws {
        let status = SecItemDelete(baseQuery(namespace: namespace) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProfileRepositoryError.keychain(status)
        }
    }

    private func baseQuery(namespace: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: namespace
        ]
    }
}

actor SecureProfileRepository: ProfileRepository {
    private let rootURL: URL
    private let keyProvider: any ProfileKeyProvider
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let indexNamespace = "profile-index-v1"

    init(
        rootURL: URL = SecureProfileRepository.defaultRootURL,
        keyProvider: any ProfileKeyProvider = KeychainProfileKeyProvider()
    ) {
        self.rootURL = rootURL
        self.keyProvider = keyProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func loadProfiles() async throws -> [LocalProfile] {
        let identifiers = try await loadIndex()
        var loaded: [LocalProfile] = []
        loaded.reserveCapacity(identifiers.count)

        for identifier in identifiers {
            let url = profileURL(identifier)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ProfileRepositoryError.missingProfileFile(identifier)
            }
            let encrypted = try Data(contentsOf: url)
            let key = try await keyProvider.key(for: profileNamespace(identifier))
            let plaintext = try Self.open(encrypted, using: key)
            loaded.append(try decoder.decode(LocalProfile.self, from: plaintext))
        }

        return loaded.sorted { $0.createdAt < $1.createdAt }
    }

    func saveProfiles(_ profiles: [LocalProfile]) async throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        let oldIDs = Set((try? await loadIndex()) ?? [])
        let newIDs = Set(profiles.map(\.id))

        // Write and verify every profile before activating the new index.
        for profile in profiles {
            let plaintext = try encoder.encode(profile)
            let key = try await keyProvider.key(for: profileNamespace(profile.id))
            let encrypted = try Self.seal(plaintext, using: key)
            let destination = profileURL(profile.id)
            try encrypted.write(to: destination, options: .atomic)
            try Self.protect(destination)

            let verificationData = try Data(contentsOf: destination)
            let verificationPlaintext = try Self.open(verificationData, using: key)
            guard try decoder.decode(LocalProfile.self, from: verificationPlaintext).id == profile.id else {
                throw ProfileRepositoryError.corruptEncryptedStore
            }
        }

        let orderedIDs = profiles.map(\.id)
        let indexData = try encoder.encode(orderedIDs)
        let indexKey = try await keyProvider.key(for: indexNamespace)
        let encryptedIndex = try Self.seal(indexData, using: indexKey)
        try encryptedIndex.write(to: indexURL, options: .atomic)
        try Self.protect(indexURL)

        // Cleanup occurs only after the new index is durably activated.
        for staleID in oldIDs.subtracting(newIDs) {
            try? FileManager.default.removeItem(at: profileURL(staleID))
            try await keyProvider.deleteKey(for: profileNamespace(staleID))
        }
    }

    private func loadIndex() async throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let encrypted = try Data(contentsOf: indexURL)
            let key = try await keyProvider.key(for: indexNamespace)
            let plaintext = try Self.open(encrypted, using: key)
            return try decoder.decode([UUID].self, from: plaintext)
        } catch let error as ProfileRepositoryError {
            throw error
        } catch {
            throw ProfileRepositoryError.corruptEncryptedStore
        }
    }

    private var indexURL: URL { rootURL.appending(path: "index.pbe") }

    private func profileURL(_ id: UUID) -> URL {
        rootURL.appending(path: "\(id.uuidString.lowercased()).pbe")
    }

    private func profileNamespace(_ id: UUID) -> String {
        "profile.\(id.uuidString.lowercased())"
    }

    private static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ProfileRepositoryError.corruptEncryptedStore
        }
        return combined
    }

    private static func open(_ encrypted: Data, using key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key)
        } catch {
            throw ProfileRepositoryError.corruptEncryptedStore
        }
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static var defaultRootURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appending(path: "PaceBack", directoryHint: .isDirectory)
            .appending(path: "Profiles", directoryHint: .isDirectory)
    }
}

actor InMemoryProfileRepository: ProfileRepository {
    private var profiles: [LocalProfile]

    init(profiles: [LocalProfile] = []) {
        self.profiles = profiles
    }

    func loadProfiles() async throws -> [LocalProfile] { profiles }

    func saveProfiles(_ profiles: [LocalProfile]) async throws {
        self.profiles = profiles
    }
}

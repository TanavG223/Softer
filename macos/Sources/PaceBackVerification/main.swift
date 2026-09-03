import CryptoKit
import Foundation
import PaceBackCore
import Security
import Darwin

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

private actor FailingRepository: ProfileRepository {
    func loadProfiles() async throws -> [LocalProfile] {
        throw ProfileRepositoryError.corruptVault
    }
    func saveProfiles(_ profiles: [LocalProfile]) async throws {
        throw ProfileRepositoryError.corruptVault
    }
    func deleteProfile(id: UUID) async throws -> ProfileDeletionOutcome {
        throw ProfileRepositoryError.corruptVault
    }
}

private struct LegacyIndexFixture: Codable {
    let profileIDs: [UUID]
}

@main
struct PaceBackVerification {
    static func main() async throws {
        setbuf(stdout, nil)
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw VerificationFailure(description: message) }
            count += 1
        }

        try check(WellbeingNeedID.allCases.count == 6, "need catalog must contain six closed choices")
        try check(WellbeingActivityID.allCases.count == 9, "activity catalog must contain nine activities")
        try check(WellbeingActivityID.harborTiles.isGame, "Harbor Tiles must be classified as play")
        try check(WellbeingActivityID.harborPath.isGame, "Harbor Path must be classified as play")

        let youngChild = LocalProfile(alias: "Young child", ageBand: .youngChild0To5, actingRole: .guardian)
        let youngActivities = Set(WellbeingActivityID.allCases.filter { $0.isAvailable(for: youngChild) })
        try check(!youngActivities.contains(.gentleBreathing), "0-5 breathing activity must stay unavailable")
        try check(!youngActivities.contains(.muscleRelease), "0-5 muscle activity must stay unavailable")
        try check(!youngActivities.contains(.harborTiles), "0-5 active game must stay unavailable")
        try check(!youngActivities.contains(.harborPath), "0-5 gentle game must stay unavailable")

        let child = LocalProfile(alias: "Child", ageBand: .child6To12, actingRole: .caregiver)
        try check(WellbeingActivityID.harborTiles.isAvailable(for: child), "6-12 caregiver-led tiles should be available")
        try check(WellbeingActivityID.harborPath.isAvailable(for: child), "6-12 caregiver-led path should be available")
        try check(!WellbeingActivityID.gentleBreathing.isAvailable(for: child), "6-12 breathing must stay unavailable")
        print("verification stage: catalog")

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let adult = LocalProfile(alias: "Adult", ageBand: .adult18To64, actingRole: .selfManaged)
        var state = WellbeingPersonalizationState(profileID: adult.id, ageBand: adult.ageBand, now: now)
        let neutral = WellbeingRecommender.recommendation(for: .notSure, profile: adult, state: state, at: now)
        try check(neutral.activityID == .orientOutside, "neutral recommendation must be deterministic")
        try check(!neutral.learnedFromExplicitFeedback, "neutral recommendation must not claim learning")
        state.record(needID: .notSure, activityID: .screenOffPause, outcome: .moreSettled, at: now)
        let adapted = WellbeingRecommender.recommendation(for: .notSure, profile: adult, state: state, at: now)
        try check(adapted.activityID == .screenOffPause, "explicit positive checkout should reorder eligible activities")
        try check(adapted.learnedFromExplicitFeedback, "adaptation label must reflect explicit feedback")
        state.record(needID: .notSure, activityID: .screenOffPause, outcome: .lessSettled, at: now)
        try check(state.isCoolingDown(.screenOffPause, at: now.addingTimeInterval(86_399)), "less-settled cooldown must last 24 hours")
        try check(!state.isCoolingDown(.screenOffPause, at: now.addingTimeInterval(86_400)), "cooldown must expire exactly at 24 hours")
        print("verification stage: recommender")

        guard case .ready(var tiles) = HarborTilesGame.prepare(ageBand: .adult18To64) else {
            throw VerificationFailure(description: "Harbor Tiles configuration must be solvable")
        }
        try check(tiles.coves.count == 3, "tiles must contain exactly three coves")
        while tiles.isActive {
            if tiles.coveNeedsAdvance {
                _ = tiles.advanceCove()
            } else if let hint = tiles.hint() {
                _ = tiles.place(pieceID: hint.pieceID, at: hint.anchor)
            } else {
                throw VerificationFailure(description: "solver-preserving tiles state became stuck")
            }
        }
        try check(tiles.resolutionID == .completed, "tiles must reach finite completion")
        try check(tiles.placementCount == HarborTilesGame.totalPlacementCount, "tiles must finish after nine placements")
        let endedTiles = tiles
        _ = tiles.place(at: HarborTilesCell(row: 0, column: 0))
        try check(tiles == endedTiles, "ended tiles game must ignore further placement")

        guard case .ready(var path) = HarborPathGame.prepare(ageBand: .adult18To64, checkpointCount: 3) else {
            throw VerificationFailure(description: "Harbor Path should prepare for adults")
        }
        try check(path.availableActionIDs.contains(.stop), "path must always expose stop while active")
        _ = path.send(.placeHarborItem)
        _ = path.send(.placeHarborItem)
        _ = path.send(.placeHarborItem)
        try check(path.resolutionID == .pathComplete, "path must end after three checkpoints")
        try check(path.checkpointResults.count == 3, "path must record only bounded session results")
        guard case .unavailable(.youngChildScreenOffOnly) = HarborPathGame.prepare(ageBand: .youngChild0To5, checkpointCount: 1) else {
            throw VerificationFailure(description: "0-5 path must be unavailable")
        }
        count += 1
        print("verification stage: games")

        let memoryRepository = InMemoryProfileRepository(profiles: [adult])
        let defaults = UserDefaults(suiteName: "PaceBackVerification.\(UUID().uuidString)")!
        let store = AppStore(
            repository: memoryRepository,
            guardianGate: AllowingGuardianGate(result: true),
            preferences: AppPreferences(defaults: defaults)
        )
        await store.load()
        let selectedProfileID = store.selectedProfile?.id
        try check(selectedProfileID == adult.id, "store must select loaded profile")
        let didStart = store.startWellbeingActivity(.harborTiles, for: .thoughtsMovingFast, at: now)
        try check(didStart, "eligible activity must start")
        let didCheckout = await store.checkoutWellbeingActivity(.moreSettled, at: now)
        try check(didCheckout, "closed checkout must persist")
        let persisted = try await memoryRepository.loadProfiles()
        try check(persisted.first?.wellbeing?.feedbackEvents.count == 1, "one checkout must create exactly one receipt")
        store.selectSupportRoute(.chat988)
        let afterSupport = try await memoryRepository.loadProfiles()
        try check(afterSupport == persisted, "support selection must never mutate profile data")

        let lockedStore = AppStore(
            repository: FailingRepository(),
            guardianGate: AllowingGuardianGate(result: true),
            preferences: AppPreferences(defaults: UserDefaults(suiteName: "PaceBackLocked.\(UUID().uuidString)")!)
        )
        await lockedStore.load()
        let workspaceError = lockedStore.workspaceErrorMessage
        let needsOnboarding = lockedStore.needsOnboarding
        let allowedLockedWrite = await lockedStore.createProfile(alias: "Blocked", ageBand: .adult18To64, actingRole: .selfManaged)
        try check(workspaceError != nil, "unreadable vault must expose locked state")
        try check(!needsOnboarding, "unreadable vault must not fall through to onboarding")
        try check(!allowedLockedWrite, "locked vault must reject writes")
        lockedStore.startGuestSession(ageBand: .adult18To64)
        try check(lockedStore.isGuestSession, "locked vault must permit a memory-only guest session")
        try check(lockedStore.selectedProfile?.alias == "Guest", "guest session must expose a temporary profile")
        try check(lockedStore.workspaceErrorMessage != nil, "guest session must not erase the encrypted-workspace failure")
        let guestStarted = lockedStore.startWellbeingActivity(.harborTiles, for: .thoughtsMovingFast, at: now)
        try check(guestStarted, "guest session must permit an eligible activity")
        let guestPersisted = await lockedStore.checkoutWellbeingActivity(.moreSettled, at: now)
        try check(!guestPersisted, "guest checkout must never claim encrypted persistence")
        try check(lockedStore.selectedProfile?.wellbeing?.feedbackEvents.count == 1, "guest checkout may adapt only in memory")
        print("verification stage: store")

        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "PaceBackVerification-\(UUID().uuidString)", directoryHint: .isDirectory)
        let service = "org.hackforhumanity.paceback.verification.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]
            SecItemDelete(query as CFDictionary)
        }
        let encrypted = EncryptedProfileRepository(directory: tempRoot, keychainService: service)
        try await encrypted.saveProfiles([adult])
        print("verification encrypted: first save")
        let encryptedLoad = try await encrypted.loadProfiles()
        print("verification encrypted: first load")
        try check(encryptedLoad == [adult], "encrypted generation must round-trip exactly")
        var changed = adult
        changed.wellbeing = WellbeingPersonalizationState(profileID: adult.id, ageBand: adult.ageBand, now: .now)
        try await encrypted.saveProfiles([changed])
        print("verification encrypted: update save")
        let updatedEncryptedLoad = try await encrypted.loadProfiles()
        let deletion = try await encrypted.deleteProfile(id: adult.id)
        let afterDeletion = try await encrypted.loadProfiles()
        try check(updatedEncryptedLoad == [changed], "same-ID update must atomically replace the active generation")
        try check(deletion == .deleted, "encrypted profile deletion must complete")
        try check(afterDeletion.isEmpty, "deleted profile must not reappear")
        print("verification stage: encrypted repository")

        let legacyRoot = FileManager.default.temporaryDirectory
            .appending(path: "PaceBackLegacyVerification-\(UUID().uuidString)", directoryHint: .isDirectory)
        let legacyService = "org.hackforhumanity.paceback.legacy-verification.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: legacyRoot)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService
            ]
            SecItemDelete(query as CFDictionary)
        }
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let legacyIndexKey = SymmetricKey(size: .bits256)
        let legacyProfileKey = SymmetricKey(size: .bits256)
        try addKey(legacyIndexKey, service: legacyService, account: "index")
        try addKey(legacyProfileKey, service: legacyService, account: "profile.\(adult.id.uuidString)")
        try seal(JSONEncoder().encode(LegacyIndexFixture(profileIDs: [adult.id])), with: legacyIndexKey)
            .write(to: legacyRoot.appending(path: "index.pbvault"))
        try seal(JSONEncoder().encode(adult), with: legacyProfileKey)
            .write(to: legacyRoot.appending(path: "\(adult.id.uuidString).pbvault"))
        let legacyRepository = EncryptedProfileRepository(directory: legacyRoot, keychainService: legacyService)
        let legacyLoad = try await legacyRepository.loadProfiles()
        try check(legacyLoad == [adult], "legacy Mac vault must remain readable")
        try await legacyRepository.saveProfiles([adult])
        let migratedNames = try FileManager.default.contentsOfDirectory(atPath: legacyRoot.path)
        try check(migratedNames.contains(where: { $0.hasPrefix("profile-\(adult.id.uuidString.lowercased())-") }), "legacy save must migrate to an immutable generation")
        try check(!migratedNames.contains("\(adult.id.uuidString).pbvault"), "superseded legacy ciphertext must be removed")
        print("verification stage: legacy vault migration")

        let riskyCopy = (WellbeingNeedID.allCases.flatMap { [$0.title, $0.detail] }
            + WellbeingActivityID.allCases.flatMap { [$0.title, $0.shortDetail] + $0.instructions })
            .joined(separator: " ").lowercased()
        for phrase in ["will calm", "cures", "guaranteed", "return you to normal"] {
            try check(!riskyCopy.contains(phrase), "catalog contains prohibited promise: \(phrase)")
        }

        print("PaceBackVerification: PASS (\(count) checks)")
    }

    private static func addKey(_ key: SymmetricKey, service: String, account: String) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ProfileRepositoryError.keychain(status) }
    }

    private static func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw ProfileRepositoryError.corruptVault }
        return combined
    }
}

import XCTest
@testable import PaceBackCore

final class RoleHandoffPolicyTests: XCTestCase {
    func testTeenGuardianEntryAuthenticatesButTeenHandoffDoesNot() {
        let teen = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .teenUser)
        let guardian = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .guardian)

        XCTAssertEqual(
            RoleHandoffPolicy.decision(for: teen, switchingTo: .guardian),
            .allowed(requiresAuthentication: true)
        )
        XCTAssertEqual(
            RoleHandoffPolicy.decision(for: guardian, switchingTo: .teenUser),
            .allowed(requiresAuthentication: false)
        )
    }

    func testEveryUnder13AdministrativeHandoffAuthenticates() {
        let guardian = LocalProfile(alias: "Child", ageBand: .child6To12, actingRole: .guardian)
        let caregiver = LocalProfile(alias: "Child", ageBand: .child6To12, actingRole: .caregiver)

        XCTAssertEqual(
            RoleHandoffPolicy.decision(for: guardian, switchingTo: .caregiver),
            .allowed(requiresAuthentication: true)
        )
        XCTAssertEqual(
            RoleHandoffPolicy.decision(for: caregiver, switchingTo: .guardian),
            .allowed(requiresAuthentication: true)
        )
    }

    func testAdultCaregiverHandoffRequiresPriorApproval() {
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
        let caregiver = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .caregiver,
            caregiverApproved: true
        )

        guard case .denied = RoleHandoffPolicy.decision(for: unapproved, switchingTo: .caregiver) else {
            return XCTFail("Unapproved adult caregiver access must fail closed")
        }
        XCTAssertEqual(
            RoleHandoffPolicy.decision(for: approved, switchingTo: .caregiver),
            .allowed(requiresAuthentication: false)
        )
        XCTAssertEqual(
            RoleHandoffPolicy.decision(for: caregiver, switchingTo: .selfManaged),
            .allowed(requiresAuthentication: true)
        )
    }

    func testRoleOutsideAgeBandIsDenied() {
        let adult = LocalProfile(alias: "Adult", ageBand: .olderAdult65Plus, actingRole: .selfManaged)

        guard case .denied = RoleHandoffPolicy.decision(for: adult, switchingTo: .guardian) else {
            return XCTFail("An invalid age-role transition must fail closed")
        }
    }
}

@MainActor
final class AppStoreRoleHandoffTests: XCTestCase {
    func testFailedTeenGuardianAuthenticationLeavesTeenModeUnchanged() async {
        let gate = RecordingGuardianGate(result: false)
        let profile = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .teenUser)
        let store = makeStore(profile: profile, gate: gate)
        await store.load()

        let switched = await store.switchActingRole(to: .guardian)
        let authorizationCount = await gate.authorizationCount()

        XCTAssertFalse(switched)
        XCTAssertEqual(store.selectedProfile?.actingRole, .teenUser)
        XCTAssertEqual(authorizationCount, 1)
        XCTAssertEqual(
            store.lastError,
            "Mac authentication was not completed. The current role is unchanged."
        )
    }

    func testGuardianCanHandOffToTeenWithoutAuthenticationAndRolePersists() async throws {
        let gate = RecordingGuardianGate(result: false)
        let profile = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .guardian)
        let repository = InMemoryProfileRepository(profiles: [profile])
        let store = AppStore(
            repository: repository,
            guardianGate: gate,
            preferences: testPreferences()
        )
        await store.load()

        let switched = await store.switchActingRole(to: .teenUser)
        let authorizationCount = await gate.authorizationCount()
        let savedProfiles = try await repository.loadProfiles()

        XCTAssertTrue(switched)
        XCTAssertEqual(store.selectedProfile?.actingRole, .teenUser)
        XCTAssertEqual(savedProfiles.first?.actingRole, .teenUser)
        XCTAssertEqual(authorizationCount, 0)
    }

    func testAdultCaregiverMustBeApprovedAndOwnerReturnAuthenticates() async {
        let gate = RecordingGuardianGate(result: false)
        let profile = LocalProfile(alias: "Adult", ageBand: .adult18To64, actingRole: .selfManaged)
        let store = makeStore(profile: profile, gate: gate)
        await store.load()

        let unapprovedSwitch = await store.switchActingRole(to: .caregiver)
        XCTAssertFalse(unapprovedSwitch)
        XCTAssertEqual(store.selectedProfile?.actingRole, .selfManaged)

        await store.setCaregiverApproved(true)
        let caregiverSwitch = await store.switchActingRole(to: .caregiver)
        XCTAssertTrue(caregiverSwitch)
        XCTAssertEqual(store.selectedProfile?.actingRole, .caregiver)

        let ownerSwitch = await store.switchActingRole(to: .selfManaged)
        let authorizationCount = await gate.authorizationCount()
        XCTAssertFalse(ownerSwitch)
        XCTAssertEqual(store.selectedProfile?.actingRole, .caregiver)
        XCTAssertEqual(authorizationCount, 1)
    }

    func testAuthenticatedAdultCaregiverCanReturnToOwnerMode() async throws {
        let gate = RecordingGuardianGate(result: true)
        let profile = LocalProfile(
            alias: "Older adult",
            ageBand: .olderAdult65Plus,
            actingRole: .caregiver,
            caregiverApproved: true
        )
        let repository = InMemoryProfileRepository(profiles: [profile])
        let store = AppStore(
            repository: repository,
            guardianGate: gate,
            preferences: testPreferences()
        )
        await store.load()

        let switched = await store.switchActingRole(to: .selfManaged)
        let savedProfiles = try await repository.loadProfiles()

        XCTAssertTrue(switched)
        XCTAssertEqual(store.selectedProfile?.actingRole, .selfManaged)
        XCTAssertEqual(savedProfiles.first?.actingRole, .selfManaged)
    }

    private func makeStore(profile: LocalProfile, gate: RecordingGuardianGate) -> AppStore {
        AppStore(
            repository: InMemoryProfileRepository(profiles: [profile]),
            guardianGate: gate,
            preferences: testPreferences()
        )
    }

    private func testPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "PaceBackRoleHandoffTests.\(UUID().uuidString)")!)
    }
}

private actor RecordingGuardianGate: GuardianGate {
    private let result: Bool
    private var reasons: [String] = []

    init(result: Bool) {
        self.result = result
    }

    func authorize(reason: String) async -> Bool {
        reasons.append(reason)
        return result
    }

    func authorizationCount() -> Int {
        reasons.count
    }
}

import XCTest
@testable import PaceBackCore

@MainActor
final class AppStorePermissionTests: XCTestCase {
    func testPediatricProfileCreationRequiresGuardianGate() async {
        let store = makeStore(gateResult: false)
        await store.load()

        let created = await store.createProfile(
            alias: "Teen",
            ageBand: .teen13To17,
            actingRole: .teenUser
        )

        XCTAssertFalse(created)
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertEqual(store.lastError, "Parent or guardian approval was not completed.")
    }

    func testAdultSelfManagedCreationDoesNotRequireGuardianGate() async {
        let store = makeStore(gateResult: false)
        await store.load()

        let created = await store.createProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .selfManaged
        )

        XCTAssertTrue(created)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.selectedProfile?.actingRole, .selfManaged)
    }

    func testGuardianAdminActionHonorsFailedAuthentication() async {
        let profile = LocalProfile(alias: "Child", ageBand: .child6To12, actingRole: .guardian)
        let store = AppStore(
            repository: InMemoryProfileRepository(profiles: [profile]),
            guardianGate: AllowingGuardianGate(result: false),
            preferences: testPreferences()
        )
        await store.load()

        let authorized = await store.authorize(.exportData)
        XCTAssertFalse(authorized)
        XCTAssertEqual(store.lastError, "Parent or guardian approval was not completed.")
    }

    private func makeStore(gateResult: Bool) -> AppStore {
        AppStore(
            repository: InMemoryProfileRepository(),
            guardianGate: AllowingGuardianGate(result: gateResult),
            preferences: testPreferences()
        )
    }

    private func testPreferences() -> AppPreferences {
        let suite = "PaceBackTests.\(UUID().uuidString)"
        return AppPreferences(defaults: UserDefaults(suiteName: suite)!)
    }
}

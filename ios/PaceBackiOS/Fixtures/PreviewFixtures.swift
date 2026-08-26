import Foundation

enum PreviewFixtures {
    static let child = LocalProfile(
        alias: "Alex",
        ageBand: .child6To12,
        actingRole: .guardian
    )

    static let teen = LocalProfile(
        alias: "River",
        ageBand: .teen13To17,
        actingRole: .teenUser
    )

    static let adult = LocalProfile(
        alias: "Sam",
        ageBand: .adult18To64,
        actingRole: .selfManaged
    )

    @MainActor
    static func store(profile: LocalProfile = adult) -> AppStore {
        let store = AppStore(
            repository: InMemoryProfileRepository(profiles: [profile]),
            aiEngine: OnDeviceUnavailableAIEngine(),
            guardianAuthenticator: AllowingGuardianAuthenticator()
        )
        store.profiles = [profile]
        store.selectedProfileID = profile.id
        store.loadingState = .ready
        store.engineAvailability = .unavailable(
            reason: "The verified macOS hybrid engine is not bundled on iOS."
        )
        return store
    }
}

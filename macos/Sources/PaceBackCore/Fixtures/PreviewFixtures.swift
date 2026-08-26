import Foundation

public enum PreviewFixtures {
    public static let child = LocalProfile(
        alias: "Alex",
        ageBand: .child6To12,
        actingRole: .guardian,
        trendEntries: sampleTrends,
        carePlanDraft: sampleCarePlan(profileID: UUID())
    )

    public static let teen = LocalProfile(
        alias: "River",
        ageBand: .teen13To17,
        actingRole: .teenUser,
        trendEntries: sampleTrends
    )

    public static let adult = LocalProfile(
        alias: "Sam",
        ageBand: .adult18To64,
        actingRole: .selfManaged,
        trendEntries: sampleTrends
    )

    public static let olderAdult = LocalProfile(
        alias: "Morgan",
        ageBand: .olderAdult65Plus,
        actingRole: .selfManaged,
        trendEntries: sampleTrends
    )

    public static let sampleTrends: [TrendEntry] = [
        TrendEntry(recordedAt: .now.addingTimeInterval(-4 * 86_400), symptomRating: 6, focusMinutes: 8),
        TrendEntry(recordedAt: .now.addingTimeInterval(-3 * 86_400), symptomRating: 5, focusMinutes: 10),
        TrendEntry(recordedAt: .now.addingTimeInterval(-2 * 86_400), symptomRating: 5, focusMinutes: 10),
        TrendEntry(recordedAt: .now.addingTimeInterval(-86_400), symptomRating: 4, focusMinutes: 12),
        TrendEntry(recordedAt: .now, symptomRating: 4, focusMinutes: 15)
    ]

    public static func sampleCarePlan(profileID: UUID) -> CarePlanDraft {
        CarePlanDraft(
            profileID: profileID,
            sourceName: "sample-clinician-plan.pdf",
            restrictions: [
                CarePlanRestriction(text: "Use short screen sessions with planned breaks.", page: 1, isConfirmed: true),
                CarePlanRestriction(text: "Discuss any increase in activity with the treating clinician.", page: 2)
            ]
        )
    }

    @MainActor
    public static func store(profile: LocalProfile = adult) -> AppStore {
        AppStore(
            repository: InMemoryProfileRepository(profiles: [profile]),
            aiEngine: MockAIEngine(delay: .milliseconds(150)),
            guardianGate: AllowingGuardianGate()
        )
    }
}

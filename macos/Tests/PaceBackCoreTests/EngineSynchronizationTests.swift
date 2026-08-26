import Foundation
import XCTest
@testable import PaceBackCore

private enum RecordedEngineEvent: Equatable, Sendable {
    case sync(UUID)
    case ask(UUID, String)
    case delete(UUID, ActingRole)
    case cancel(UUID, String)
}

private actor RecordingAIEngine: AIEngine {
    private var recordedEvents: [RecordedEngineEvent] = []
    private let askDelay: Duration?

    init(askDelay: Duration? = nil) {
        self.askDelay = askDelay
    }

    func health() async throws -> EngineHealth {
        EngineHealth(
            status: "ok",
            version: "test",
            databaseReady: true,
            fts5Ready: true,
            releaseMode: true,
            storageDriver: "test",
            storageEncryptionActive: true,
            networkToolsEnabled: false
        )
    }

    func syncProfile(_ profile: LocalProfile) async throws {
        recordedEvents.append(.sync(profile.id))
    }

    func deleteProfile(id: UUID, actingRole: ActingRole) async throws {
        recordedEvents.append(.delete(id, actingRole))
    }

    func ask(_ query: EvidenceQuery) async throws -> EvidenceAnswer {
        recordedEvents.append(.ask(query.profileID, query.runID))
        if let askDelay { try await Task.sleep(for: askDelay) }
        return EvidenceAnswer(
            runID: query.runID,
            answer: "I could not verify an answer.",
            supportStatus: .insufficientInformation,
            citations: [],
            route: "test",
            stopReason: "noEvidence",
            usage: RunUsage(
                retrievedTokens: 0,
                inputTokens: 1,
                outputTokens: 1,
                retrievalRounds: 0,
                latencyMS: 0
            )
        )
    }

    func cancel(runID: String, profileID: UUID) async {
        recordedEvents.append(.cancel(profileID, runID))
    }

    func events() -> [RecordedEngineEvent] { recordedEvents }
}

@MainActor
final class EngineSynchronizationTests: XCTestCase {
    func testAskSynchronizesProfileBeforeCreatingRun() async {
        let profile = LocalProfile(
            alias: "Evidence",
            ageBand: .adult18To64,
            actingRole: .selfManaged
        )
        let engine = RecordingAIEngine()
        let model = AskEvidenceModel()
        model.question = "What does my confirmed plan say?"

        model.ask(profile: profile, engine: engine)

        let events = await waitForEvents(count: 2, engine: engine)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .sync(profile.id))
        guard case .ask(let askedProfileID, _) = events.last else {
            return XCTFail("Expected an ask event after profile synchronization.")
        }
        XCTAssertEqual(askedProfileID, profile.id)
    }

    func testCancelWhileLoadingUsesTheClientGeneratedRunID() async {
        let profile = LocalProfile(
            alias: "Cancel",
            ageBand: .adult18To64,
            actingRole: .selfManaged
        )
        let engine = RecordingAIEngine(askDelay: .seconds(5))
        let model = AskEvidenceModel()
        model.question = "What is supported?"

        model.ask(profile: profile, engine: engine)
        let started = await waitForEvents(count: 2, engine: engine)
        guard case .ask(_, let runID) = started.last else {
            return XCTFail("Expected an in-flight ask event.")
        }

        model.cancel(profileID: profile.id, engine: engine)
        let events = await waitForEvents(count: 3, engine: engine)

        XCTAssertEqual(events.last, .cancel(profile.id, runID))
        XCTAssertEqual(model.state, .idle)
    }

    func testLoadThenDeleteQueuesMatchingSidecarDeletion() async {
        let profile = LocalProfile(
            alias: "Private",
            ageBand: .adult18To64,
            actingRole: .selfManaged
        )
        let engine = RecordingAIEngine()
        let store = AppStore(
            repository: InMemoryProfileRepository(profiles: [profile]),
            aiEngine: engine,
            guardianGate: AllowingGuardianGate(result: true),
            preferences: testPreferences()
        )

        await store.load()
        let deleted = await store.deleteSelectedProfile()

        XCTAssertTrue(deleted)
        XCTAssertTrue(store.profiles.isEmpty)
        let events = await engine.events()
        XCTAssertEqual(events, [.sync(profile.id), .delete(profile.id, .selfManaged)])
    }

    func testConfirmedCarePlanChangePersistsThenResynchronizesProfile() async {
        let profileID = UUID()
        let restriction = CarePlanRestriction(
            text: "Use the clinician-confirmed school break.",
            page: 2
        )
        let profile = LocalProfile(
            id: profileID,
            alias: "Student",
            ageBand: .child6To12,
            actingRole: .guardian,
            carePlanDraft: CarePlanDraft(
                profileID: profileID,
                sourceName: "plan.pdf",
                restrictions: [restriction]
            )
        )
        let engine = RecordingAIEngine()
        let store = AppStore(
            repository: InMemoryProfileRepository(profiles: [profile]),
            aiEngine: engine,
            guardianGate: AllowingGuardianGate(result: true),
            preferences: testPreferences()
        )

        await store.load()
        await store.setRestrictionConfirmed(id: restriction.id, confirmed: true)

        let events = await engine.events()
        XCTAssertEqual(events, [.sync(profile.id), .sync(profile.id)])
        XCTAssertEqual(store.selectedProfile?.carePlanDraft?.restrictions.first?.isConfirmed, true)
    }

    private func waitForEvents(
        count: Int,
        engine: RecordingAIEngine
    ) async -> [RecordedEngineEvent] {
        for _ in 0..<100 {
            let events = await engine.events()
            if events.count >= count { return events }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await engine.events()
    }

    private func testPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "PaceBackSyncTests.\(UUID().uuidString)")!)
    }
}

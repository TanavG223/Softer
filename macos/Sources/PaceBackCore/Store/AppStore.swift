import Foundation
import Observation

public enum AppSheet: String, Identifiable, Sendable {
    case dangerSigns
    case addProfile

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class AppPreferences {
    public var readingMode: ReadingMode {
        didSet { defaults.set(readingMode.rawValue, forKey: Keys.readingMode) }
    }
    public var textScale: Double {
        didSet { defaults.set(textScale, forKey: Keys.textScale) }
    }
    public var comfortableSpacing: Bool {
        didSet { defaults.set(comfortableSpacing, forKey: Keys.comfortableSpacing) }
    }
    public var reduceMotionOverride: Bool {
        didSet { defaults.set(reduceMotionOverride, forKey: Keys.reduceMotion) }
    }
    public var readAnswersAloud: Bool {
        didSet { defaults.set(readAnswersAloud, forKey: Keys.readAnswersAloud) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readingMode = defaults.string(forKey: Keys.readingMode)
            .flatMap(ReadingMode.init(rawValue:)) ?? .standard
        let storedScale = defaults.double(forKey: Keys.textScale)
        self.textScale = storedScale == 0 ? 1 : max(0.9, min(storedScale, 1.5))
        self.comfortableSpacing = defaults.object(forKey: Keys.comfortableSpacing) as? Bool ?? true
        self.reduceMotionOverride = defaults.bool(forKey: Keys.reduceMotion)
        self.readAnswersAloud = defaults.bool(forKey: Keys.readAnswersAloud)
    }

    private enum Keys {
        static let readingMode = "paceback.readingMode"
        static let textScale = "paceback.textScale"
        static let comfortableSpacing = "paceback.comfortableSpacing"
        static let reduceMotion = "paceback.reduceMotion"
        static let readAnswersAloud = "paceback.readAnswersAloud"
    }
}

@MainActor
@Observable
public final class AppStore {
    public var profiles: [LocalProfile] = []
    public var selectedProfileID: UUID?
    public var selectedSection: AppSection = .today
    public var presentedSheet: AppSheet?
    public var isLoading = false
    public private(set) var hasLoaded = false
    public var lastError: String?
    public var safetyAcknowledged = false

    public let preferences: AppPreferences
    public let aiEngine: any AIEngine
    public let simplifier: any SimplificationService
    public let guardianGate: any GuardianGate
    public let carePlanImporter: any CarePlanImporting

    @ObservationIgnored private let repository: any ProfileRepository
    @ObservationIgnored private var didLoad = false

    public init(
        repository: any ProfileRepository = EncryptedProfileRepository(),
        aiEngine: any AIEngine = UnavailableAIEngine(),
        simplifier: any SimplificationService = LocalSimplificationService(),
        guardianGate: any GuardianGate = LocalAuthenticationGuardianGate(),
        carePlanImporter: any CarePlanImporting = PDFCarePlanImporter(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.repository = repository
        self.aiEngine = aiEngine
        self.simplifier = simplifier
        self.guardianGate = guardianGate
        self.carePlanImporter = carePlanImporter
        self.preferences = preferences
    }

    public var selectedProfile: LocalProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    public var needsOnboarding: Bool { hasLoaded && profiles.isEmpty }

    public func load() async {
        guard !didLoad else { return }
        isLoading = true
        defer {
            isLoading = false
            didLoad = true
            hasLoaded = true
        }
        do {
            profiles = try await repository.loadProfiles().map { profile in
                var safe = profile
                safe.actingRole = RolePolicy.normalizedRole(profile.actingRole, for: profile.ageBand)
                return safe
            }
            selectedProfileID = profiles.first?.id
            for profile in profiles {
                await synchronizeProfile(profile, reportFailure: false)
            }
        } catch {
            lastError = error.localizedDescription
            profiles = []
        }
    }

    @discardableResult
    public func createProfile(alias: String, ageBand: AgeBand, actingRole: ActingRole) async -> Bool {
        let cleanedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAlias.isEmpty, cleanedAlias.count <= 40 else {
            lastError = "Use an alias between 1 and 40 characters."
            return false
        }
        if ageBand.isPediatric {
            let approved = await guardianGate.authorize(
                reason: "A parent or guardian must initialize a child or teen PaceBack profile."
            )
            guard approved else {
                lastError = "Parent or guardian approval was not completed."
                return false
            }
        }
        let profile = LocalProfile(
            alias: cleanedAlias,
            ageBand: ageBand,
            actingRole: RolePolicy.normalizedRole(actingRole, for: ageBand),
            caregiverApproved: ageBand.isUnder13 && actingRole == .caregiver
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        safetyAcknowledged = true
        guard await persistProfiles() else { return false }
        await synchronizeProfile(profile)
        return true
    }

    public func updateProfile(_ profile: LocalProfile) async -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
        var safeProfile = profile
        safeProfile.actingRole = RolePolicy.normalizedRole(profile.actingRole, for: profile.ageBand)
        profiles[index] = safeProfile
        guard await persistProfiles() else { return false }
        await synchronizeProfile(safeProfile)
        return true
    }

    public func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        selectedSection = .today
    }

    public func authorize(_ permission: ProfilePermission) async -> Bool {
        guard let profile = selectedProfile, RolePolicy.permits(permission, profile: profile) else {
            lastError = "This role does not have permission for that action."
            return false
        }
        guard RolePolicy.requiresAdministrativeGate(permission, profile: profile) else { return true }
        let success = await guardianGate.authorize(reason: "A parent or guardian must approve this change.")
        if !success { lastError = "Parent or guardian approval was not completed." }
        return success
    }

    public func deleteSelectedProfile() async -> Bool {
        guard await authorize(.deleteProfile), let profile = selectedProfile else { return false }
        do {
            let deletionOutcome = try await repository.deleteProfile(id: profile.id)
            profiles.removeAll { $0.id == profile.id }
            selectedProfileID = profiles.first?.id
            selectedSection = .today
            if case .deletedWithResiduals(let details) = deletionOutcome {
                lastError = "Profile access was removed, but cleanup could not be fully verified: \(details.joined(separator: "; "))"
            }
            do {
                try await aiEngine.deleteProfile(id: profile.id, actingRole: profile.actingRole)
            } catch AIEngineError.unavailable {
                // SwitchingAIEngine retains a tombstone and replays it when the
                // authenticated sidecar becomes available.
            } catch {
                lastError = "The profile was deleted locally. Its local evidence index will retry deletion."
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func recordTrend(symptomRating: Int, focusMinutes: Int, note: String = "") async {
        guard let index = selectedProfileIndex else { return }
        profiles[index].trendEntries.append(
            TrendEntry(symptomRating: symptomRating, focusMinutes: focusMinutes, note: note)
        )
        _ = await persistProfiles()
    }

    public func importCarePlan(from url: URL) async -> Bool {
        guard await authorize(.importDocuments),
              let profile = selectedProfile,
              let index = selectedProfileIndex else { return false }
        do {
            profiles[index].carePlanDraft = try await carePlanImporter.importDraft(from: url, profileID: profile.id)
            guard await persistProfiles() else { return false }
            await synchronizeProfile(profiles[index])
            return true
        } catch is CancellationError {
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func setRestrictionConfirmed(id: UUID, confirmed: Bool) async {
        guard await authorize(.manageCarePlan),
              let index = selectedProfileIndex,
              let restrictionIndex = profiles[index].carePlanDraft?.restrictions.firstIndex(where: { $0.id == id })
        else { return }
        profiles[index].carePlanDraft?.restrictions[restrictionIndex].isConfirmed = confirmed
        if await persistProfiles() {
            await synchronizeProfile(profiles[index])
        }
    }

    public func addConfirmedPreference(_ preference: String) async {
        let clean = preference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = selectedProfileIndex else { return }
        if !profiles[index].confirmedPreferences.contains(clean) {
            profiles[index].confirmedPreferences.append(clean)
            _ = await persistProfiles()
        }
    }

    public func setCaregiverApproved(_ approved: Bool) async {
        guard let index = selectedProfileIndex,
              profiles[index].ageBand == .adult18To64 || profiles[index].ageBand == .olderAdult65Plus,
              profiles[index].actingRole == .selfManaged else { return }
        profiles[index].caregiverApproved = approved
        if await persistProfiles() {
            await synchronizeProfile(profiles[index])
        }
    }

    public func removeConfirmedPreference(_ preference: String) async {
        guard let index = selectedProfileIndex else { return }
        profiles[index].confirmedPreferences.removeAll { $0 == preference }
        _ = await persistProfiles()
    }

    private var selectedProfileIndex: Int? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileID }
    }

    private func persistProfiles() async -> Bool {
        do {
            try await repository.saveProfiles(profiles)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func synchronizeProfile(_ profile: LocalProfile, reportFailure: Bool = true) async {
        do {
            try await aiEngine.syncProfile(profile)
        } catch AIEngineError.unavailable {
            // The production switching engine queues this state while its local
            // helper is starting and replays it after the authenticated handshake.
        } catch {
            if reportFailure {
                lastError = "Saved locally. The local evidence index will retry synchronization."
            }
        }
    }
}

public enum AskEvidenceState: Equatable, Sendable {
    case idle
    case loading
    case loaded(EvidenceAnswer)
    case failed(String)
}

@MainActor
@Observable
public final class AskEvidenceModel {
    public var question = ""
    public private(set) var state: AskEvidenceState = .idle

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var currentRunID: String?

    public init() {}

    public func ask(profile: LocalProfile, engine: any AIEngine) {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            state = .failed("Enter a question or select a suggested question.")
            return
        }
        task?.cancel()
        state = .loading
        let query = EvidenceQuery(question: clean, profile: profile)
        currentRunID = query.runID
        task = Task {
            do {
                try await engine.syncProfile(profile)
                let answer = try await engine.ask(query)
                guard !Task.isCancelled, currentRunID == query.runID else { return }
                currentRunID = nil
                state = .loaded(answer)
            } catch is CancellationError {
                if currentRunID == query.runID {
                    currentRunID = nil
                    state = .idle
                }
            } catch {
                if currentRunID == query.runID {
                    currentRunID = nil
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func cancel(profileID: UUID, engine: any AIEngine) {
        let runID: String?
        if let currentRunID {
            runID = currentRunID
        } else if case .loaded(let answer) = state {
            runID = answer.runID
        } else {
            runID = nil
        }
        if let runID {
            Task { await engine.cancel(runID: runID, profileID: profileID) }
        }
        currentRunID = nil
        task?.cancel()
        task = nil
        state = .idle
    }
}

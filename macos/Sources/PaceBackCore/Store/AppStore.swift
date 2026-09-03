import Foundation
import Observation

public enum AppSheet: String, Identifiable, Sendable {
    case addProfile
    case support
    public var id: String { rawValue }
}

@MainActor
@Observable
public final class AppPreferences {
    public var textScale: Double { didSet { defaults.set(textScale, forKey: Keys.textScale) } }
    public var comfortableSpacing: Bool { didSet { defaults.set(comfortableSpacing, forKey: Keys.comfortableSpacing) } }
    public var reduceMotionOverride: Bool { didSet { defaults.set(reduceMotionOverride, forKey: Keys.reduceMotion) } }
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedScale = defaults.double(forKey: Keys.textScale)
        self.textScale = storedScale == 0 ? 1 : max(0.9, min(storedScale, 1.5))
        self.comfortableSpacing = defaults.object(forKey: Keys.comfortableSpacing) as? Bool ?? true
        self.reduceMotionOverride = defaults.bool(forKey: Keys.reduceMotion)
    }

    private enum Keys {
        static let textScale = "paceback.textScale"
        static let comfortableSpacing = "paceback.comfortableSpacing"
        static let reduceMotion = "paceback.reduceMotion"
    }
}

@MainActor
@Observable
public final class AppStore {
    public private(set) var profiles: [LocalProfile] = []
    public var selectedProfileID: UUID?
    public var selectedSection: AppSection = .calm
    public var presentedSheet: AppSheet?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isGuestSession = false
    public var lastError: String?
    public private(set) var workspaceErrorMessage: String?
    public private(set) var selectedWellbeingNeed: WellbeingNeedID?
    public private(set) var wellbeingRecommendation: WellbeingRecommendation?
    public private(set) var activeWellbeingSession: WellbeingSession?
    public private(set) var lastWellbeingOutcome: WellbeingOutcome?
    public private(set) var selectedSupportRoute: SupportRoute?

    public let preferences: AppPreferences
    public let guardianGate: any GuardianGate
    @ObservationIgnored private let repository: any ProfileRepository

    public init(
        repository: any ProfileRepository = EncryptedProfileRepository(),
        guardianGate: any GuardianGate = LocalAuthenticationGuardianGate(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.repository = repository
        self.guardianGate = guardianGate
        self.preferences = preferences
    }

    public var selectedProfile: LocalProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    public var needsOnboarding: Bool {
        hasLoaded && !isGuestSession && workspaceErrorMessage == nil && profiles.isEmpty
    }

    public var canUseWellbeingActivities: Bool {
        workspaceErrorMessage == nil || isGuestSession
    }

    public func load() async {
        guard !hasLoaded, !isLoading else { return }
        await loadWorkspace()
    }

    public func retryWorkspaceLoad() async {
        guard !isLoading else { return }
        await loadWorkspace()
    }

    private func loadWorkspace() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            var loaded = try await repository.loadProfiles()
            var rejectedWellbeingState = false
            for index in loaded.indices {
                guard RolePolicy.validRoles(for: loaded[index].ageBand).contains(loaded[index].actingRole) else {
                    throw ProfileRepositoryError.corruptVault
                }
                if let wellbeing = loaded[index].wellbeing,
                   !wellbeing.belongs(to: loaded[index], at: .now) {
                    loaded[index].wellbeing = nil
                    rejectedWellbeingState = true
                }
            }
            profiles = loaded
            selectedProfileID = loaded.first?.id
            isGuestSession = false
            workspaceErrorMessage = nil
            if rejectedWellbeingState {
                lastError = "Wellbeing activity memory did not match its encrypted profile and was not used."
            }
        } catch {
            // Fail closed: unreadable encrypted data must never look like a
            // first launch, where onboarding could overwrite recoverable data.
            profiles = []
            selectedProfileID = nil
            workspaceErrorMessage = error.localizedDescription
        }
    }

    /// Starts a temporary, memory-only session. This is deliberately separate
    /// from the encrypted repository: it never writes a profile, key, activity,
    /// or checkout to disk and remains available when Keychain access fails.
    public func startGuestSession(ageBand: AgeBand) {
        guard [.teen13To17, .adult18To64, .olderAdult65Plus].contains(ageBand) else {
            lastError = "Guest sessions are available for ages 13 and older. A caregiver can use Support without a profile."
            return
        }
        let role: ActingRole = ageBand == .teen13To17 ? .teenUser : .selfManaged
        let guest = LocalProfile(alias: "Guest", ageBand: ageBand, actingRole: role)
        profiles = [guest]
        selectedProfileID = guest.id
        isGuestSession = true
        selectedSection = .calm
        clearTransientWellbeingState()
    }

    public func returnToEncryptedWorkspace() async {
        guard isGuestSession, !isLoading else { return }
        isGuestSession = false
        profiles = []
        selectedProfileID = nil
        selectedSection = .calm
        clearTransientWellbeingState()
        await loadWorkspace()
    }

    @discardableResult
    public func createProfile(alias: String, ageBand: AgeBand, actingRole: ActingRole) async -> Bool {
        guard workspaceErrorMessage == nil, !isGuestSession else {
            lastError = "The encrypted workspace is locked. Retry access before creating a profile."
            return false
        }
        let cleanedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAlias.isEmpty, cleanedAlias.count <= 40 else {
            lastError = "Use an alias between 1 and 40 characters."
            return false
        }
        guard RolePolicy.validRoles(for: ageBand).contains(actingRole) else {
            lastError = "That role is not available for the selected age experience."
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
            actingRole: actingRole,
            caregiverApproved: ageBand.isUnder13 && actingRole == .caregiver
        )
        let updated = profiles + [profile]
        do {
            try await repository.saveProfiles(updated)
            profiles = updated
            selectedProfileID = profile.id
            selectedSection = .calm
            clearTransientWellbeingState()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func updateProfile(_ profile: LocalProfile) async -> Bool {
        guard workspaceErrorMessage == nil,
              let index = profiles.firstIndex(where: { $0.id == profile.id }),
              RolePolicy.validRoles(for: profile.ageBand).contains(profile.actingRole) else { return false }
        var safeProfile = profile
        if let wellbeing = safeProfile.wellbeing, !wellbeing.belongs(to: safeProfile, at: .now) {
            safeProfile.wellbeing = nil
        }
        var updated = profiles
        updated[index] = safeProfile
        do {
            try await repository.saveProfiles(updated)
            profiles = updated
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        selectedSection = .calm
        clearTransientWellbeingState()
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
        guard workspaceErrorMessage == nil,
              await authorize(.deleteProfile),
              let profile = selectedProfile else { return false }
        do {
            let outcome = try await repository.deleteProfile(id: profile.id)
            profiles.removeAll { $0.id == profile.id }
            selectedProfileID = profiles.first?.id
            selectedSection = .calm
            clearTransientWellbeingState()
            if case .deletedWithResiduals(let details) = outcome {
                lastError = "Profile access was removed, but cleanup could not be fully verified: \(details.joined(separator: "; "))"
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public var availableWellbeingActivities: [WellbeingActivityID] {
        guard let profile = selectedProfile else { return [] }
        return WellbeingActivityID.allCases.filter { $0.isAvailable(for: profile) }
    }

    @discardableResult
    public func recommendWellbeingActivity(for needID: WellbeingNeedID, at now: Date = .now) -> WellbeingRecommendation? {
        guard let profile = selectedProfile else { clearTransientWellbeingState(); return nil }
        let state = validWellbeingState(for: profile, at: now)
        let recommendation = WellbeingRecommender.recommendation(for: needID, profile: profile, state: state, at: now)
        selectedWellbeingNeed = needID
        wellbeingRecommendation = recommendation
        activeWellbeingSession = nil
        lastWellbeingOutcome = nil
        return recommendation
    }

    @discardableResult
    public func startWellbeingActivity(_ activityID: WellbeingActivityID, for needID: WellbeingNeedID, at now: Date = .now) -> Bool {
        guard canUseWellbeingActivities,
              let profile = selectedProfile,
              activityID.isAvailable(for: profile) else {
            lastError = "That activity is not available for this profile’s age and role."
            return false
        }
        let state = validWellbeingState(for: profile, at: now)
        guard !state.isCoolingDown(activityID, at: now) else {
            lastError = "That exact activity is paused for 24 hours after a Less settled check-out. Choose another option."
            return false
        }
        selectedWellbeingNeed = needID
        activeWellbeingSession = WellbeingSession(profileID: profile.id, needID: needID, activityID: activityID, startedAt: now)
        lastWellbeingOutcome = nil
        return true
    }

    @discardableResult
    public func startRecommendedWellbeingActivity(at now: Date = .now) -> Bool {
        guard let recommendation = wellbeingRecommendation, recommendation.canStart else {
            lastError = "No automatic activity is available right now. You can open Support or return later."
            return false
        }
        return startWellbeingActivity(recommendation.activityID, for: recommendation.needID, at: now)
    }

    @discardableResult
    public func checkoutWellbeingActivity(_ outcome: WellbeingOutcome, at now: Date = .now) async -> Bool {
        guard canUseWellbeingActivities,
              let session = activeWellbeingSession,
              selectedProfileID == session.profileID,
              let profileIndex = profiles.firstIndex(where: { $0.id == session.profileID }) else {
            lastError = "The activity no longer matches the active profile. Nothing was saved."
            activeWellbeingSession = nil
            return false
        }
        var updated = profiles
        var state = validWellbeingState(for: updated[profileIndex], at: now)
        state.record(needID: session.needID, activityID: session.activityID, outcome: outcome, at: now)
        updated[profileIndex].wellbeing = state
        if isGuestSession {
            profiles = updated
            activeWellbeingSession = nil
            lastWellbeingOutcome = outcome
            wellbeingRecommendation = WellbeingRecommender.recommendation(
                for: session.needID,
                profile: updated[profileIndex],
                state: state,
                at: now
            )
            return false
        }
        do {
            try await repository.saveProfiles(updated)
            profiles = updated
            activeWellbeingSession = nil
            lastWellbeingOutcome = outcome
            wellbeingRecommendation = WellbeingRecommender.recommendation(
                for: session.needID,
                profile: updated[profileIndex],
                state: state,
                at: now
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func cancelWellbeingActivity() { activeWellbeingSession = nil }
    public func selectSupportRoute(_ route: SupportRoute) { selectedSupportRoute = route }
    public func clearSupportRoute() { selectedSupportRoute = nil }

    private func validWellbeingState(for profile: LocalProfile, at now: Date) -> WellbeingPersonalizationState {
        guard let state = profile.wellbeing, state.belongs(to: profile, at: now) else {
            return WellbeingPersonalizationState(profileID: profile.id, ageBand: profile.ageBand, now: now)
        }
        return state
    }

    private func clearTransientWellbeingState() {
        selectedWellbeingNeed = nil
        wellbeingRecommendation = nil
        activeWellbeingSession = nil
        lastWellbeingOutcome = nil
        selectedSupportRoute = nil
    }
}

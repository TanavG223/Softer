import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    enum LoadingState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    enum EvidenceAttemptState: Equatable {
        case idle
        case checking
        case answer(EvidenceResponse)
        case abstention(String)
        case unavailable(String)
    }

    var profiles: [LocalProfile] = []
    var selectedProfileID: UUID?
    var loadingState: LoadingState = .idle
    var engineAvailability: AIEngineAvailability = .unavailable(reason: "Checking this device…")
    var evidenceAttempt: EvidenceAttemptState = .idle
    var modelPackStatus: ModelPackStatus = .checking
    var modelPackCapacity: ModelPackCapacity?
    var readingMode: ReadingMode = .standard
    var lastError: String?

    private let repository: any ProfileRepository
    private let aiEngine: any AIEngine
    private let guardianAuthenticator: any GuardianAuthenticator
    private let modelPackStore: ModelPackStore
    private var modelInstallTask: Task<Void, Never>?

    init(
        repository: any ProfileRepository,
        aiEngine: any AIEngine,
        guardianAuthenticator: any GuardianAuthenticator,
        modelPackStore: ModelPackStore = ModelPackStore()
    ) {
        self.repository = repository
        self.aiEngine = aiEngine
        self.guardianAuthenticator = guardianAuthenticator
        self.modelPackStore = modelPackStore
    }

    convenience init(launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        if launchArguments.contains("-PaceBackSyntheticProfile") {
            let demo = LocalProfile(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                alias: "Demo",
                ageBand: .adult18To64,
                actingRole: .selfManaged,
                createdAt: Date(timeIntervalSince1970: 1_788_000_000)
            )
            let modelPackStore = ModelPackStore()
            self.init(
                repository: InMemoryProfileRepository(profiles: [demo]),
                aiEngine: LocalEvidenceEngine(modelPackProvider: modelPackStore),
                guardianAuthenticator: AllowingGuardianAuthenticator(),
                modelPackStore: modelPackStore
            )
            return
        }
        #endif

        let modelPackStore = ModelPackStore()
        self.init(
            repository: SecureProfileRepository(),
            aiEngine: LocalEvidenceEngine(modelPackProvider: modelPackStore),
            guardianAuthenticator: LocalGuardianAuthenticator(),
            modelPackStore: modelPackStore
        )
    }

    var selectedProfile: LocalProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    func load() async {
        guard loadingState == .idle else { return }
        loadingState = .loading
        modelPackStatus = await modelPackStore.inspectInstallation()
        await refreshModelPackCapacity()
        engineAvailability = await aiEngine.availability()
        do {
            profiles = try await repository.loadProfiles()
            selectedProfileID = profiles.first?.id
            loadingState = .ready
        } catch {
            loadingState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func refreshModelPackStatus() async {
        guard !modelPackStatus.isWorking else { return }
        modelPackStatus = .checking
        modelPackStatus = await modelPackStore.inspectInstallation()
        await refreshModelPackCapacity()
        engineAvailability = await aiEngine.availability()
    }

    func installModelPack(
        networkPolicy: ModelPackNetworkPolicy,
        force: Bool = false
    ) async {
        guard modelInstallTask == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            let finalStatus = await modelPackStore.install(
                networkPolicy: networkPolicy,
                force: force
            ) { [weak self] status in
                await MainActor.run {
                    self?.modelPackStatus = status
                }
            }
            guard !Task.isCancelled else { return }
            modelPackStatus = finalStatus
            engineAvailability = await aiEngine.availability()
            await refreshModelPackCapacity()
        }
        modelInstallTask = task
        await task.value
        modelInstallTask = nil
    }

    func cancelModelPackInstall() {
        modelInstallTask?.cancel()
        modelPackStore.cancel()
    }

    func deleteModelPack() async {
        cancelModelPackInstall()
        modelPackStatus = await modelPackStore.deleteInstallation()
        engineAvailability = await aiEngine.availability()
        await refreshModelPackCapacity()
    }

    private func refreshModelPackCapacity() async {
        switch await modelPackStore.preflight() {
        case .success(let capacity):
            modelPackCapacity = capacity
        case .failure(.insufficientSpace(let required, let available)):
            modelPackCapacity = ModelPackCapacity(
                availableBytes: available,
                requiredBytes: required
            )
        case .failure:
            modelPackCapacity = nil
        }
    }

    @discardableResult
    func createProfile(alias: String, ageBand: AgeBand, actingRole: ActingRole) async -> Bool {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Choose an alias before creating the profile."
            return false
        }

        guard RolePolicy.creationRoles(for: ageBand).contains(actingRole) else {
            lastError = ageBand == .teen13To17
                ? "A parent or guardian must initialize a teen profile."
                : "An adult profile must be initialized by its owner before caregiver sharing can be approved."
            return false
        }

        if ageBand.isPediatric {
            let authenticated = await guardianAuthenticator.authenticate(
                reason: "A parent, guardian, or caregiver must authenticate before creating this pediatric PaceBack profile."
            )
            guard authenticated else {
                lastError = "A pediatric profile was not created because device authentication did not complete."
                return false
            }
        }

        let profile = LocalProfile(alias: trimmed, ageBand: ageBand, actingRole: actingRole)
        let updatedProfiles = profiles + [profile]
        do {
            try await repository.saveProfiles(updatedProfiles)
            profiles = updatedProfiles
            selectedProfileID = profile.id
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func setCaregiverApproval(_ approved: Bool) async -> Bool {
        guard let profile = selectedProfile,
              !profile.ageBand.isPediatric,
              profile.actingRole == .selfManaged,
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            lastError = "Only the profile owner can change caregiver approval."
            return false
        }

        var updatedProfiles = profiles
        updatedProfiles[index].caregiverApproved = approved
        do {
            try await repository.saveProfiles(updatedProfiles)
            profiles = updatedProfiles
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func switchRole(to targetRole: ActingRole) async -> Bool {
        guard let profile = selectedProfile,
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }

        let decision = RoleHandoffPolicy.decision(for: profile, switchingTo: targetRole)
        switch decision {
        case .denied(let reason):
            lastError = reason
            return false
        case .allowed(let requiresAuthentication):
            if requiresAuthentication {
                let authenticated = await guardianAuthenticator.authenticate(
                    reason: "Authenticate before changing the active PaceBack role for \(profile.alias)."
                )
                guard authenticated else {
                    lastError = "The role did not change because device authentication did not complete."
                    return false
                }
            }
        }

        var updatedProfiles = profiles
        updatedProfiles[index].actingRole = targetRole
        do {
            try await repository.saveProfiles(updatedProfiles)
            profiles = updatedProfiles
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        evidenceAttempt = .idle
    }

    func attemptEvidence(question: String) async {
        guard let profile = selectedProfile else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        evidenceAttempt = .checking
        do {
            let response = try await aiEngine.ask(
                EvidenceRequest(
                    question: trimmed,
                    profileID: profile.id,
                    ageBand: profile.ageBand,
                    actingRole: profile.actingRole,
                    careContext: profile.careContext
                )
            )
            let trimmedAnswer = response.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAnswer.isEmpty else {
                evidenceAttempt = .unavailable("The local engine returned no displayable result.")
                return
            }
            if response.isSourceLinked {
                guard !response.citations.isEmpty else {
                    evidenceAttempt = .unavailable(
                        "The local source-link contract was incomplete, so no evidence answer was shown."
                    )
                    return
                }
                evidenceAttempt = .answer(response)
            } else {
                evidenceAttempt = .abstention(trimmedAnswer)
            }
        } catch {
            evidenceAttempt = .unavailable(error.localizedDescription)
        }
    }

    func authorize(_ permission: ProfilePermission) async -> Bool {
        guard let profile = selectedProfile,
              RolePolicy.permits(permission, profile: profile) else {
            lastError = "This role cannot use that protected action."
            return false
        }

        guard RolePolicy.requiresAdministrativeGate(permission, profile: profile) else {
            return true
        }

        let allowed = await guardianAuthenticator.authenticate(
            reason: "Authenticate to open protected PaceBack controls for \(profile.alias)."
        )
        if !allowed {
            lastError = "Device authentication was cancelled or unavailable."
        }
        return allowed
    }

    func deleteSelectedProfile() async -> Bool {
        guard let profile = selectedProfile else { return false }
        guard await authorize(.deleteProfile) else { return false }

        let updatedProfiles = profiles.filter { $0.id != profile.id }
        do {
            try await repository.saveProfiles(updatedProfiles)
            profiles = updatedProfiles
            selectedProfileID = profiles.first?.id
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

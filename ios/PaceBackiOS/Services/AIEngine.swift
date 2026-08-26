import Foundation

enum AIEngineAvailability: Equatable, Sendable {
    case ready(modelName: String)
    case unavailable(reason: String)

    var title: String {
        switch self {
        case .ready:
            "Local evidence engine ready"
        case .unavailable:
            "Evidence engine unavailable on this iOS device"
        }
    }

    var detail: String {
        switch self {
        case .ready(let modelName):
            "Integrity-checked \(modelName) models are installed for private on-device retrieval."
        case .unavailable(let reason):
            reason
        }
    }

    var isReady: Bool {
        if case .ready = self { true } else { false }
    }
}

struct EvidenceRequest: Equatable, Sendable {
    let question: String
    let profileID: UUID
    let ageBand: AgeBand
    let actingRole: ActingRole
    let careContext: CareContext

    var evidenceScopes: Set<String> { ["allAges", ageBand.rawValue] }
}

struct EvidenceResponse: Equatable, Sendable {
    let answer: String
    let citations: [EvidenceCitation]
    /// Every displayed excerpt is a literal substring of its cited bundled
    /// passage. This is a provenance statement, not medical verification.
    let isSourceLinked: Bool
    let localInferenceMilliseconds: Int?

    static func abstention(
        _ reason: String,
        localInferenceMilliseconds: Int? = nil
    ) -> EvidenceResponse {
        EvidenceResponse(
            answer: reason,
            citations: [],
            isSourceLinked: false,
            localInferenceMilliseconds: localInferenceMilliseconds
        )
    }
}

struct EvidenceCitation: Identifiable, Equatable, Sendable {
    let number: Int
    let title: String
    let published: String
    let sourceID: String
    let passageID: String
    let url: URL
    let exactQuote: String
    let contentHash: String

    var id: String { passageID }

    var locator: String {
        "\(sourceID) · \(passageID) · source date \(published)"
    }
}

enum AIEngineError: LocalizedError, Equatable, Sendable {
    case onDeviceModelUnavailable
    case invalidModelPack
    case invalidRequest
    case inferenceFailed
    case evidenceCorpusUnavailable

    var errorDescription: String? {
        switch self {
        case .onDeviceModelUnavailable:
            "Download and verify the local evidence models before asking a question. PaceBack will not use a cloud fallback."
        case .invalidModelPack:
            "The active local model pack no longer matches the verified PaceBack contract. Delete it and download it again."
        case .invalidRequest:
            "This profile, role, or question did not pass the local evidence safety contract."
        case .inferenceFailed:
            "Local model inference could not be verified, so PaceBack did not show an evidence answer."
        case .evidenceCorpusUnavailable:
            "The bundled, age-scoped evidence corpus could not be verified, so PaceBack did not show an answer."
        }
    }
}

protocol AIEngine: Sendable {
    func availability() async -> AIEngineAvailability
    func ask(_ request: EvidenceRequest) async throws -> EvidenceResponse
}

actor OnDeviceUnavailableAIEngine: AIEngine {
    func availability() async -> AIEngineAvailability {
        .unavailable(
            reason: "The verified local hybrid-search models have not been installed. Static safety guidance remains available, and no question leaves this device."
        )
    }

    func ask(_ request: EvidenceRequest) async throws -> EvidenceResponse {
        _ = request
        throw AIEngineError.onDeviceModelUnavailable
    }
}

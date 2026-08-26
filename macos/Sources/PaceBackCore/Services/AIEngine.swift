import CryptoKit
import Foundation

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct EngineHealth: Codable, Hashable, Sendable {
    public let status: String
    public let version: String
    public let databaseReady: Bool
    public let fts5Ready: Bool
    public let releaseMode: Bool
    public let storageDriver: String
    public let storageEncryptionActive: Bool
    public let networkToolsEnabled: Bool

    public init(
        status: String,
        version: String,
        databaseReady: Bool,
        fts5Ready: Bool,
        releaseMode: Bool,
        storageDriver: String,
        storageEncryptionActive: Bool,
        networkToolsEnabled: Bool
    ) {
        self.status = status
        self.version = version
        self.databaseReady = databaseReady
        self.fts5Ready = fts5Ready
        self.releaseMode = releaseMode
        self.storageDriver = storageDriver
        self.storageEncryptionActive = storageEncryptionActive
        self.networkToolsEnabled = networkToolsEnabled
    }
}

public struct EngineModelComponent: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let purpose: String
    public let localOnly: Bool
    public let active: Bool
    public let activation: String
    public let modelID: String?
    public let revision: String?
    public let artifactSHA256: String?
    public let dimensions: Int?
    public let provider: String?
    public let failureReason: String?
}

public struct EngineModelManifest: Codable, Hashable, Sendable {
    public let components: [EngineModelComponent]
    public let modelPackID: String?
    public let modelPackActivation: String
    public let webSearchEnabled: Bool
    public let codeExecutionEnabled: Bool
    public let runtimeWeightUpdatesEnabled: Bool
    public let storageDriver: String
    public let storageEncryptionActive: Bool
}

public protocol AIEngine: Sendable {
    func health() async throws -> EngineHealth
    func syncProfile(_ profile: LocalProfile) async throws
    func deleteProfile(id: UUID, actingRole: ActingRole) async throws
    func ask(_ query: EvidenceQuery) async throws -> EvidenceAnswer
    func cancel(runID: String, profileID: UUID) async
}

public enum AIEngineError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case unavailable
    case unverifiedAnswer
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The local evidence engine returned an invalid response."
        case .httpStatus(let status): "The local evidence engine returned HTTP \(status)."
        case .unavailable: "The local evidence engine is unavailable."
        case .unverifiedAnswer: "I could not verify an answer."
        case .invalidConfiguration: "The local evidence engine must use loopback with a non-empty launch token."
        }
    }
}

public actor URLSidecarAIEngine: AIEngine {
    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, bearerToken: String, session: URLSession? = nil) throws {
        let loopbackHosts = Set(["127.0.0.1", "::1", "localhost"])
        guard baseURL.scheme == "http",
              let host = baseURL.host?.lowercased(),
              loopbackHosts.contains(host),
              !bearerToken.isEmpty else {
            throw AIEngineError.invalidConfiguration
        }
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            self.session = URLSession(
                configuration: configuration,
                delegate: NoRedirectURLSessionDelegate(),
                delegateQueue: nil
            )
        }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func health() async throws -> EngineHealth {
        var request = URLRequest(url: baseURL.appending(path: "v1/health"))
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(EngineHealth.self, from: data)
    }

    public func modelManifest() async throws -> EngineModelManifest {
        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(EngineModelManifest.self, from: data)
    }

    public func syncProfile(_ profile: LocalProfile) async throws {
        var request = authenticatedRequest(
            path: "v1/profiles/\(profile.id.uuidString)",
            method: "PUT"
        )
        request.httpBody = try encoder.encode(
            SidecarProfileCreate(
                alias: profile.alias,
                ageBand: profile.ageBand,
                ownerRole: profile.sidecarOwnerRole,
                caregiverAccess: profile.ageBand.isPediatric ? false : profile.caregiverApproved
            )
        )
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)

        try await reconcileConfirmedCarePlan(for: profile)
    }

    public func deleteProfile(id: UUID, actingRole: ActingRole) async throws {
        var request = authenticatedRequest(
            path: "v1/profiles/\(id.uuidString)",
            method: "DELETE"
        )
        request.setValue(actingRole.rawValue, forHTTPHeaderField: "X-Acting-Role")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response, allowingNotFound: true)
    }

    public func ask(_ query: EvidenceQuery) async throws -> EvidenceAnswer {
        var request = authenticatedRequest(path: "v1/runs", method: "POST")
        request.httpBody = try encoder.encode(query)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let answer = try decoder.decode(EvidenceAnswer.self, from: data)
        guard answer.runID == query.runID else { throw AIEngineError.invalidResponse }
        let citationRequired = answer.supportStatus == .verified || answer.supportStatus == .partial
        guard !citationRequired || !answer.citations.isEmpty else {
            throw AIEngineError.unverifiedAnswer
        }
        return answer
    }

    public func cancel(runID: String, profileID: UUID) async {
        guard let encodedID = runID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        let endpoint = baseURL.appending(path: "v1/runs/\(encodedID)")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "profileID", value: profileID.uuidString)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    private func reconcileConfirmedCarePlan(for profile: LocalProfile) async throws {
        let documents = try await listDocuments(profileID: profile.id)
        let clinicianPlans = documents.filter { $0.sourceKind == "clinicianPlan" }
        guard let desiredContent = profile.confirmedCarePlanContent else {
            for document in clinicianPlans {
                try await deleteDocument(
                    profileID: profile.id,
                    documentID: document.documentID,
                    actingRole: profile.sidecarOwnerRole
                )
            }
            return
        }

        let desiredHash = SHA256.hash(data: Data(desiredContent.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let matchingDocumentID = clinicianPlans.first(where: {
            $0.contentHash == desiredHash && $0.evidenceScope == profile.ageBand.specificScope
        })?.documentID

        if matchingDocumentID == nil {
            var request = authenticatedRequest(
                path: "v1/profiles/\(profile.id.uuidString)/documents",
                method: "POST"
            )
            request.httpBody = try encoder.encode(
                SidecarDocumentCreate(
                    actingRole: profile.sidecarOwnerRole,
                    title: "Confirmed clinician care plan",
                    content: desiredContent,
                    sourceKind: "clinicianPlan",
                    evidenceScope: profile.ageBand.specificScope
                )
            )
            let (_, response) = try await session.data(for: request)
            try Self.validate(response)
        }

        // Activate the desired document before removing stale versions so a failed
        // import never leaves the profile without its last confirmed plan.
        for document in clinicianPlans where document.documentID != matchingDocumentID {
            try await deleteDocument(
                profileID: profile.id,
                documentID: document.documentID,
                actingRole: profile.sidecarOwnerRole
            )
        }
    }

    private func listDocuments(profileID: UUID) async throws -> [SidecarDocument] {
        let request = authenticatedRequest(
            path: "v1/profiles/\(profileID.uuidString)/documents",
            method: "GET"
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode([SidecarDocument].self, from: data)
    }

    private func deleteDocument(
        profileID: UUID,
        documentID: String,
        actingRole: ActingRole
    ) async throws {
        guard let encodedDocumentID = documentID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            throw AIEngineError.invalidResponse
        }
        var request = authenticatedRequest(
            path: "v1/profiles/\(profileID.uuidString)/documents/\(encodedDocumentID)",
            method: "DELETE"
        )
        request.setValue(actingRole.rawValue, forHTTPHeaderField: "X-Acting-Role")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response, allowingNotFound: true)
    }

    private func authenticatedRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if method == "POST" || method == "PUT" || method == "PATCH" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func validate(
        _ response: URLResponse,
        allowingNotFound: Bool = false
    ) throws {
        guard let http = response as? HTTPURLResponse else { throw AIEngineError.invalidResponse }
        if allowingNotFound, http.statusCode == 404 { return }
        guard (200..<300).contains(http.statusCode) else { throw AIEngineError.httpStatus(http.statusCode) }
    }
}

private struct SidecarProfileCreate: Encodable, Sendable {
    let alias: String
    let ageBand: AgeBand
    let ownerRole: ActingRole
    let caregiverAccess: Bool
}

private struct SidecarDocumentCreate: Encodable, Sendable {
    let actingRole: ActingRole
    let title: String
    let content: String
    let sourceKind: String
    let evidenceScope: EvidenceScope
}

private struct SidecarDocument: Decodable, Sendable {
    let documentID: String
    let sourceKind: String
    let evidenceScope: EvidenceScope
    let contentHash: String
}

private extension LocalProfile {
    var sidecarOwnerRole: ActingRole {
        ageBand.isPediatric ? .guardian : .selfManaged
    }

    var confirmedCarePlanContent: String? {
        let confirmed = carePlanDraft?.restrictions.compactMap { restriction -> String? in
            let text = restriction.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard restriction.isConfirmed, !text.isEmpty else { return nil }
            return "Page \(max(1, restriction.page)): \(text)"
        } ?? []
        guard !confirmed.isEmpty else { return nil }
        return (["Confirmed clinician-plan restrictions."] + confirmed).joined(separator: "\n\n")
    }
}

public actor UnavailableAIEngine: AIEngine {
    public init() {}

    public func health() async throws -> EngineHealth { throw AIEngineError.unavailable }
    public func syncProfile(_ profile: LocalProfile) async throws { throw AIEngineError.unavailable }
    public func deleteProfile(id: UUID, actingRole: ActingRole) async throws {
        throw AIEngineError.unavailable
    }
    public func ask(_ query: EvidenceQuery) async throws -> EvidenceAnswer {
        throw AIEngineError.unavailable
    }
    public func cancel(runID: String, profileID: UUID) async {}
}

public actor MockAIEngine: AIEngine {
    private let delay: Duration
    private var cancelledRuns: Set<String> = []

    public init(delay: Duration = .milliseconds(550)) {
        self.delay = delay
    }

    public func health() async throws -> EngineHealth {
        EngineHealth(
            status: "preview-fixture",
            version: "mock-1.0",
            databaseReady: true,
            fts5Ready: true,
            releaseMode: true,
            storageDriver: "mock",
            storageEncryptionActive: true,
            networkToolsEnabled: false
        )
    }

    public func syncProfile(_ profile: LocalProfile) async throws {}

    public func deleteProfile(id: UUID, actingRole: ActingRole) async throws {}

    public func ask(_ query: EvidenceQuery) async throws -> EvidenceAnswer {
        try await Task.sleep(for: delay)
        try Task.checkCancellation()

        let runID = query.runID
        return EvidenceAnswer(
            runID: runID,
            answer: "Preview fixture only. No evidence answer was produced.",
            supportStatus: .insufficientInformation,
            citations: [],
            route: "previewFixture",
            stopReason: "noEvidence",
            usage: RunUsage(
                retrievedTokens: 0,
                inputTokens: query.question.count / 4,
                outputTokens: 10,
                retrievalRounds: 0,
                latencyMS: 550
            )
        )
    }

    public func cancel(runID: String, profileID: UUID) async {
        cancelledRuns.insert(runID)
    }
}

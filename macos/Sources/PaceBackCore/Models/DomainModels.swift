import Foundation

public enum AgeBand: String, CaseIterable, Codable, Identifiable, Sendable {
    case youngChild0To5
    case child6To12
    case teen13To17
    case adult18To64
    case olderAdult65Plus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .youngChild0To5: "Young child (0–5)"
        case .child6To12: "Child (6–12)"
        case .teen13To17: "Teen (13–17)"
        case .adult18To64: "Adult (18–64)"
        case .olderAdult65Plus: "Older adult (65+)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .youngChild0To5: "0–5"
        case .child6To12: "6–12"
        case .teen13To17: "13–17"
        case .adult18To64: "18–64"
        case .olderAdult65Plus: "65+"
        }
    }

    public var isUnder13: Bool {
        self == .youngChild0To5 || self == .child6To12
    }

    public var isPediatric: Bool {
        isUnder13 || self == .teen13To17
    }

    public var specificScope: EvidenceScope {
        switch self {
        case .youngChild0To5: .youngChild0To5
        case .child6To12: .child6To12
        case .teen13To17: .teen13To17
        case .adult18To64: .adult18To64
        case .olderAdult65Plus: .olderAdult65Plus
        }
    }

    public var defaultCareContext: CareContext {
        switch self {
        case .youngChild0To5: .home
        case .child6To12, .teen13To17: .school
        case .adult18To64: .work
        case .olderAdult65Plus: .dailyLiving
        }
    }
}

public enum ActingRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case selfManaged
    case teenUser
    case guardian
    case caregiver

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .selfManaged: "Self"
        case .teenUser: "Teen"
        case .guardian: "Parent or guardian"
        case .caregiver: "Caregiver"
        }
    }
}

public enum CareContext: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case school
    case work
    case dailyLiving

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .school: "School"
        case .work: "Work"
        case .dailyLiving: "Daily living"
        }
    }
}

public enum ProfilePermission: String, CaseIterable, Codable, Sendable {
    case useGuidedSessions
    case deleteProfile
    case changeSettings
}

public enum EvidenceScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case allAges
    case youngChild0To5
    case child6To12
    case teen13To17
    case adult18To64
    case olderAdult65Plus

    public var id: String { rawValue }
}

public struct LocalProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var alias: String
    public var ageBand: AgeBand
    public var actingRole: ActingRole
    public var careContext: CareContext
    public var caregiverApproved: Bool
    public let createdAt: Date
    public var trendEntries: [TrendEntry]
    public var carePlanDraft: CarePlanDraft?
    public var confirmedPreferences: [String]
    /// Explicit, closed wellbeing check-outs stored inside this profile's
    /// existing encrypted vault. Optional keeps older profile payloads decodable.
    public var wellbeing: WellbeingPersonalizationState?

    public init(
        id: UUID = UUID(),
        alias: String,
        ageBand: AgeBand,
        actingRole: ActingRole,
        careContext: CareContext? = nil,
        caregiverApproved: Bool = false,
        createdAt: Date = .now,
        trendEntries: [TrendEntry] = [],
        carePlanDraft: CarePlanDraft? = nil,
        confirmedPreferences: [String] = [],
        wellbeing: WellbeingPersonalizationState? = nil
    ) {
        self.id = id
        self.alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ageBand = ageBand
        self.actingRole = actingRole
        self.careContext = careContext ?? ageBand.defaultCareContext
        self.caregiverApproved = caregiverApproved
        self.createdAt = createdAt
        self.trendEntries = trendEntries
        self.carePlanDraft = carePlanDraft
        self.confirmedPreferences = confirmedPreferences
        self.wellbeing = wellbeing
    }
}

public enum RolePolicy {
    public static func validRoles(for ageBand: AgeBand) -> [ActingRole] {
        switch ageBand {
        case .youngChild0To5, .child6To12:
            [.guardian, .caregiver]
        case .teen13To17:
            [.teenUser, .guardian]
        case .adult18To64, .olderAdult65Plus:
            [.selfManaged, .caregiver]
        }
    }

    public static func normalizedRole(_ role: ActingRole, for ageBand: AgeBand) -> ActingRole {
        validRoles(for: ageBand).contains(role) ? role : validRoles(for: ageBand)[0]
    }

    public static func permits(_ permission: ProfilePermission, profile: LocalProfile) -> Bool {
        guard validRoles(for: profile.ageBand).contains(profile.actingRole) else { return false }

        if profile.actingRole == .caregiver,
           !profile.ageBand.isUnder13,
           !profile.caregiverApproved {
            return false
        }

        switch permission {
        case .useGuidedSessions:
            return true
        case .deleteProfile, .changeSettings:
            switch profile.ageBand {
            case .youngChild0To5, .child6To12:
                return profile.actingRole == .guardian || profile.actingRole == .caregiver
            case .teen13To17:
                return profile.actingRole == .guardian
            case .adult18To64, .olderAdult65Plus:
                return profile.actingRole == .selfManaged
            }
        }
    }

    public static func requiresAdministrativeGate(
        _ permission: ProfilePermission,
        profile: LocalProfile
    ) -> Bool {
        guard [ProfilePermission.deleteProfile, .changeSettings]
            .contains(permission) else { return false }
        return profile.ageBand.isPediatric
    }
}

public enum ReadingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case brief
    case standard
    case full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brief: "Brief"
        case .standard: "Standard"
        case .full: "Full detail"
        }
    }

    public var maximumParagraphs: Int {
        switch self {
        case .brief: 2
        case .standard: 4
        case .full: 8
        }
    }
}

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case calm
    case toolkit
    case play
    case support
    case privacy
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .calm: "Calm"
        case .toolkit: "Toolkit"
        case .play: "Play"
        case .support: "Support"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .calm: "sparkles"
        case .toolkit: "square.grid.2x2"
        case .play: "gamecontroller"
        case .support: "heart.text.square"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

public struct SourceCitation: Identifiable, Codable, Hashable, Sendable {
    public var id: String { sourceID }
    public let sourceID: String
    public let title: String
    public let url: URL?
    public let page: Int?
    public let quote: String

    public init(sourceID: String, title: String, url: URL? = nil, page: Int? = nil, quote: String) {
        self.sourceID = sourceID
        self.title = title
        self.url = url
        self.page = page
        self.quote = quote
    }
}

public enum SupportStatus: String, Codable, Sendable {
    case verified
    case partial
    case insufficientInformation
    case dangerSignDetected
    case cancelled
}

public struct RunUsage: Codable, Hashable, Sendable {
    public let retrievedTokens: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let retrievalRounds: Int
    public let latencyMS: Double

    public init(
        retrievedTokens: Int,
        inputTokens: Int,
        outputTokens: Int,
        retrievalRounds: Int,
        latencyMS: Double
    ) {
        self.retrievedTokens = retrievedTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.retrievalRounds = retrievalRounds
        self.latencyMS = latencyMS
    }
}

public struct EvidenceQuery: Codable, Hashable, Sendable {
    public let runID: String
    public let question: String
    public let profileID: UUID
    public let ageBand: AgeBand
    public let actingRole: ActingRole
    public let careContext: CareContext
    public let evidenceScope: [EvidenceScope]
    public let maxOutputTokens: Int

    public init(
        question: String,
        profile: LocalProfile,
        maxOutputTokens: Int = 500,
        runID: String = UUID().uuidString
    ) {
        self.runID = runID
        self.question = question
        self.profileID = profile.id
        self.ageBand = profile.ageBand
        self.actingRole = profile.actingRole
        self.careContext = profile.careContext
        self.evidenceScope = [.allAges, profile.ageBand.specificScope]
        self.maxOutputTokens = max(100, min(maxOutputTokens, 800))
    }
}

public struct EvidenceAnswer: Identifiable, Codable, Hashable, Sendable {
    public var id: String { runID }
    public let runID: String
    public let answer: String
    public let supportStatus: SupportStatus
    public let citations: [SourceCitation]
    public let route: String
    public let stopReason: String
    public let usage: RunUsage

    public init(
        runID: String,
        answer: String,
        supportStatus: SupportStatus,
        citations: [SourceCitation],
        route: String,
        stopReason: String,
        usage: RunUsage
    ) {
        self.runID = runID
        self.answer = answer
        self.supportStatus = supportStatus
        self.citations = citations
        self.route = route
        self.stopReason = stopReason
        self.usage = usage
    }
}

public struct TrendEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let symptomRating: Int
    public let focusMinutes: Int
    public let note: String

    public init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        symptomRating: Int,
        focusMinutes: Int,
        note: String = ""
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.symptomRating = max(0, min(symptomRating, 10))
        self.focusMinutes = max(0, focusMinutes)
        self.note = note
    }
}

public struct CarePlanRestriction: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let page: Int
    public var isConfirmed: Bool

    public init(id: UUID = UUID(), text: String, page: Int, isConfirmed: Bool = false) {
        self.id = id
        self.text = text
        self.page = page
        self.isConfirmed = isConfirmed
    }
}

public struct CarePlanDraft: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let profileID: UUID
    public let sourceName: String
    public let importedAt: Date
    public var restrictions: [CarePlanRestriction]

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        sourceName: String,
        importedAt: Date = .now,
        restrictions: [CarePlanRestriction]
    ) {
        self.id = id
        self.profileID = profileID
        self.sourceName = sourceName
        self.importedAt = importedAt
        self.restrictions = restrictions
    }
}

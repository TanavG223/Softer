import Foundation

enum AgeBand: String, CaseIterable, Codable, Identifiable, Sendable {
    case youngChild0To5
    case child6To12
    case teen13To17
    case adult18To64
    case olderAdult65Plus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youngChild0To5: "Young child (0–5)"
        case .child6To12: "Child (6–12)"
        case .teen13To17: "Teen (13–17)"
        case .adult18To64: "Adult (18–64)"
        case .olderAdult65Plus: "Older adult (65+)"
        }
    }

    var compactTitle: String {
        switch self {
        case .youngChild0To5: "0–5"
        case .child6To12: "6–12"
        case .teen13To17: "13–17"
        case .adult18To64: "18–64"
        case .olderAdult65Plus: "65+"
        }
    }

    var isUnder13: Bool {
        self == .youngChild0To5 || self == .child6To12
    }

    var isPediatric: Bool { isUnder13 || self == .teen13To17 }

    var defaultCareContext: CareContext {
        switch self {
        case .youngChild0To5: .home
        case .child6To12, .teen13To17: .school
        case .adult18To64: .work
        case .olderAdult65Plus: .dailyLiving
        }
    }

    var experienceSummary: String {
        switch self {
        case .youngChild0To5:
            "Caregiver-operated with infant and young-child danger signs."
        case .child6To12:
            "Caregiver-managed with short, calm, guided experiences."
        case .teen13To17:
            "Teen sessions with protected guardian administration."
        case .adult18To64:
            "Self-managed or explicitly shared with a caregiver."
        case .olderAdult65Plus:
            "Clear reading modes with optional approved caregiver support."
        }
    }
}

enum ActingRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case selfManaged
    case teenUser
    case guardian
    case caregiver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selfManaged: "Self"
        case .teenUser: "Teen"
        case .guardian: "Parent or guardian"
        case .caregiver: "Caregiver"
        }
    }
}

enum CareContext: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case school
    case work
    case dailyLiving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .school: "School"
        case .work: "Work"
        case .dailyLiving: "Daily living"
        }
    }
}

enum ProfilePermission: String, CaseIterable, Codable, Sendable {
    case useGuidedSessions
    case askEvidence
    case manageCarePlan
    case importDocuments
    case exportData
    case deleteProfile
    case changeSettings
}

struct LocalProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var alias: String
    var ageBand: AgeBand
    var actingRole: ActingRole
    var careContext: CareContext
    var caregiverApproved: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        alias: String,
        ageBand: AgeBand,
        actingRole: ActingRole,
        careContext: CareContext? = nil,
        caregiverApproved: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.alias = String(alias.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        self.ageBand = ageBand
        self.actingRole = RolePolicy.normalizedRole(actingRole, for: ageBand)
        self.careContext = careContext ?? ageBand.defaultCareContext
        self.caregiverApproved = caregiverApproved
        self.createdAt = createdAt
    }
}

enum ReadingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case brief
    case standard
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: "Brief"
        case .standard: "Standard"
        case .full: "Full detail"
        }
    }

    var symbol: String {
        switch self {
        case .brief: "text.line.first.and.arrowtriangle.forward"
        case .standard: "text.alignleft"
        case .full: "text.justify.left"
        }
    }
}

struct TrendEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let recordedAt: Date
    let symptomRating: Int
    let focusMinutes: Int

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        symptomRating: Int,
        focusMinutes: Int
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.symptomRating = min(10, max(0, symptomRating))
        self.focusMinutes = max(0, focusMinutes)
    }
}

struct EvidenceSource: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let url: URL

    static let trusted: [EvidenceSource] = [
        EvidenceSource(
            id: "cdc-danger-signs",
            title: "CDC concussion signs and symptoms",
            detail: "Static danger signs used by the emergency check.",
            url: URL(string: "https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html")!
        ),
        EvidenceSource(
            id: "cdc-school",
            title: "CDC HEADS UP: returning to school",
            detail: "Guidance for families, schools, and healthcare providers.",
            url: URL(string: "https://www.cdc.gov/heads-up/guidelines/returning-to-school.html")!
        ),
        EvidenceSource(
            id: "amsterdam-consensus",
            title: "Amsterdam concussion consensus",
            detail: "International consensus statement on concussion in sport.",
            url: URL(string: "https://bjsm.bmj.com/content/57/11/695")!
        )
    ]
}

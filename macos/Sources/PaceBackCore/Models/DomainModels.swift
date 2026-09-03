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

public struct LocalProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var alias: String
    public var ageBand: AgeBand
    public var actingRole: ActingRole
    public var careContext: CareContext
    public var caregiverApproved: Bool
    public let createdAt: Date
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
        wellbeing: WellbeingPersonalizationState? = nil
    ) {
        self.id = id
        self.alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ageBand = ageBand
        self.actingRole = actingRole
        self.careContext = careContext ?? ageBand.defaultCareContext
        self.caregiverApproved = caregiverApproved
        self.createdAt = createdAt
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

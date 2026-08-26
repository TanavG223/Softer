import Foundation

enum RolePolicy {
    static func creationRoles(for ageBand: AgeBand) -> [ActingRole] {
        switch ageBand {
        case .youngChild0To5, .child6To12:
            [.guardian, .caregiver]
        case .teen13To17:
            [.guardian]
        case .adult18To64, .olderAdult65Plus:
            [.selfManaged]
        }
    }

    static func validRoles(for ageBand: AgeBand) -> [ActingRole] {
        switch ageBand {
        case .youngChild0To5, .child6To12:
            [.guardian, .caregiver]
        case .teen13To17:
            [.teenUser, .guardian]
        case .adult18To64, .olderAdult65Plus:
            [.selfManaged, .caregiver]
        }
    }

    static func normalizedRole(_ role: ActingRole, for ageBand: AgeBand) -> ActingRole {
        validRoles(for: ageBand).contains(role) ? role : validRoles(for: ageBand)[0]
    }

    static func permits(_ permission: ProfilePermission, profile: LocalProfile) -> Bool {
        guard validRoles(for: profile.ageBand).contains(profile.actingRole) else { return false }

        if profile.actingRole == .caregiver,
           !profile.ageBand.isUnder13,
           !profile.caregiverApproved {
            return false
        }

        switch permission {
        case .useGuidedSessions, .askEvidence:
            return true
        case .manageCarePlan, .importDocuments:
            switch profile.ageBand {
            case .youngChild0To5, .child6To12:
                return profile.actingRole == .guardian || profile.actingRole == .caregiver
            case .teen13To17:
                return profile.actingRole == .guardian
            case .adult18To64, .olderAdult65Plus:
                return profile.actingRole == .selfManaged
            }
        case .exportData:
            switch profile.ageBand {
            case .youngChild0To5, .child6To12:
                return true
            case .teen13To17:
                return profile.actingRole == .guardian
            case .adult18To64, .olderAdult65Plus:
                return profile.actingRole == .selfManaged || profile.actingRole == .caregiver
            }
        case .deleteProfile, .changeSettings:
            switch profile.ageBand {
            case .youngChild0To5, .child6To12:
                return true
            case .teen13To17:
                return profile.actingRole == .guardian
            case .adult18To64, .olderAdult65Plus:
                return profile.actingRole == .selfManaged
            }
        }
    }

    static func requiresAdministrativeGate(
        _ permission: ProfilePermission,
        profile: LocalProfile
    ) -> Bool {
        guard [.manageCarePlan, .importDocuments, .exportData, .deleteProfile, .changeSettings]
            .contains(permission) else { return false }
        return profile.ageBand.isPediatric
    }
}

enum RoleHandoffDecision: Equatable, Sendable {
    case allowed(requiresAuthentication: Bool)
    case denied(reason: String)
}

enum RoleHandoffPolicy {
    static func decision(
        for profile: LocalProfile,
        switchingTo targetRole: ActingRole
    ) -> RoleHandoffDecision {
        guard RolePolicy.validRoles(for: profile.ageBand).contains(profile.actingRole),
              RolePolicy.validRoles(for: profile.ageBand).contains(targetRole) else {
            return .denied(reason: "That role is not available for this age group.")
        }
        guard profile.actingRole != targetRole else {
            return .allowed(requiresAuthentication: false)
        }

        switch profile.ageBand {
        case .youngChild0To5, .child6To12:
            return .allowed(requiresAuthentication: true)
        case .teen13To17:
            return .allowed(requiresAuthentication: targetRole == .guardian)
        case .adult18To64, .olderAdult65Plus:
            switch targetRole {
            case .caregiver:
                guard profile.actingRole == .selfManaged, profile.caregiverApproved else {
                    return .denied(reason: "The profile owner must approve caregiver access first.")
                }
                return .allowed(requiresAuthentication: false)
            case .selfManaged:
                return .allowed(requiresAuthentication: true)
            case .teenUser, .guardian:
                return .denied(reason: "That role is not available for this age group.")
            }
        }
    }
}

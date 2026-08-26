import Foundation

public enum RoleHandoffDecision: Equatable, Sendable {
    case allowed(requiresAuthentication: Bool)
    case denied(reason: String)
}

/// Keeps role transitions separate from feature permissions so a view cannot
/// accidentally elevate a profile by assigning `actingRole` directly.
public enum RoleHandoffPolicy {
    public static func decision(
        for profile: LocalProfile,
        switchingTo targetRole: ActingRole
    ) -> RoleHandoffDecision {
        guard RolePolicy.validRoles(for: profile.ageBand).contains(profile.actingRole) else {
            return .denied(reason: "The current role is not valid for this age group.")
        }
        guard RolePolicy.validRoles(for: profile.ageBand).contains(targetRole) else {
            return .denied(reason: "That role is not available for this age group.")
        }
        guard profile.actingRole != targetRole else {
            return .allowed(requiresAuthentication: false)
        }

        switch profile.ageBand {
        case .youngChild0To5, .child6To12:
            // Both available roles can administer an under-13 profile.
            return .allowed(requiresAuthentication: true)

        case .teen13To17:
            // A guardian can deliberately hand the session back to the teen,
            // while entering protected guardian controls requires authentication.
            return .allowed(requiresAuthentication: targetRole == .guardian)

        case .adult18To64, .olderAdult65Plus:
            switch targetRole {
            case .caregiver:
                guard profile.actingRole == .selfManaged, profile.caregiverApproved else {
                    return .denied(
                        reason: "The profile owner must approve caregiver access before this handoff."
                    )
                }
                return .allowed(requiresAuthentication: false)
            case .selfManaged:
                // An approved caregiver cannot claim owner controls without
                // authenticating as a device owner first.
                return .allowed(requiresAuthentication: true)
            case .teenUser, .guardian:
                return .denied(reason: "That role is not available for this age group.")
            }
        }
    }

    public static func authenticationReason(
        for profile: LocalProfile,
        switchingTo targetRole: ActingRole
    ) -> String {
        switch profile.ageBand {
        case .youngChild0To5, .child6To12:
            "Authenticate with this Mac before changing who administers this child profile."
        case .teen13To17:
            "Authenticate with this Mac before entering parent or guardian controls."
        case .adult18To64, .olderAdult65Plus:
            "Authenticate with this Mac before returning to profile-owner controls."
        }
    }
}

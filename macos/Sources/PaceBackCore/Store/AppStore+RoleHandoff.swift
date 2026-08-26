import Foundation

public extension AppStore {
    /// Changes the active role only after applying the age-specific handoff
    /// policy. `updateProfile` is the single persistence and engine-sync path.
    @discardableResult
    func switchActingRole(to targetRole: ActingRole) async -> Bool {
        guard var profile = selectedProfile else {
            lastError = "Select a profile before changing roles."
            return false
        }

        switch RoleHandoffPolicy.decision(for: profile, switchingTo: targetRole) {
        case .denied(let reason):
            lastError = reason
            return false

        case .allowed(let requiresAuthentication):
            if requiresAuthentication {
                let approved = await guardianGate.authorize(
                    reason: RoleHandoffPolicy.authenticationReason(
                        for: profile,
                        switchingTo: targetRole
                    )
                )
                guard approved else {
                    lastError = "Mac authentication was not completed. The current role is unchanged."
                    return false
                }
            }

            guard profile.actingRole != targetRole else {
                lastError = nil
                return true
            }

            profile.actingRole = targetRole
            let updated = await updateProfile(profile)
            if updated { lastError = nil }
            return updated
        }
    }
}

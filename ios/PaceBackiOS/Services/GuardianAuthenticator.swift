import Foundation
import LocalAuthentication

protocol GuardianAuthenticator: Sendable {
    func authenticate(reason: String) async -> Bool
}

actor LocalGuardianAuthenticator: GuardianAuthenticator {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}

actor AllowingGuardianAuthenticator: GuardianAuthenticator {
    func authenticate(reason: String) async -> Bool {
        _ = reason
        return true
    }
}

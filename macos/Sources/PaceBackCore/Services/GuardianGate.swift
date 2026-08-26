import Foundation
import LocalAuthentication

public protocol GuardianGate: Sendable {
    func authorize(reason: String) async -> Bool
}

public struct LocalAuthenticationGuardianGate: GuardianGate {
    public init() {}

    public func authorize(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                continuation.resume(returning: false)
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

public struct AllowingGuardianGate: GuardianGate {
    public let result: Bool

    public init(result: Bool = true) {
        self.result = result
    }

    public func authorize(reason: String) async -> Bool { result }
}

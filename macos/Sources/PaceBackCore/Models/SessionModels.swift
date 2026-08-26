import Foundation

public struct FocusSessionConfiguration: Codable, Hashable, Sendable {
    public var focusMinutes: Int
    public var restMinutes: Int

    public init(focusMinutes: Int = 15, restMinutes: Int = 5) {
        self.focusMinutes = max(1, min(focusMinutes, 60))
        self.restMinutes = max(1, min(restMinutes, 30))
    }
}

public enum FocusSessionPhase: String, Codable, Equatable, Sendable {
    case ready
    case focusing
    case paused
    case resting
    case completed
    case stoppedEarly
}

public struct FocusSessionMachine: Codable, Equatable, Sendable {
    public private(set) var phase: FocusSessionPhase = .ready
    public private(set) var elapsedFocusSeconds = 0
    public private(set) var elapsedRestSeconds = 0
    public let configuration: FocusSessionConfiguration

    public init(configuration: FocusSessionConfiguration) {
        self.configuration = configuration
    }

    public var focusSecondsRemaining: Int {
        max(0, configuration.focusMinutes * 60 - elapsedFocusSeconds)
    }

    public var restSecondsRemaining: Int {
        max(0, configuration.restMinutes * 60 - elapsedRestSeconds)
    }

    public var isRunning: Bool {
        phase == .focusing || phase == .resting
    }

    public mutating func start() {
        guard phase == .ready else { return }
        phase = .focusing
    }

    public mutating func pause() {
        guard phase == .focusing || phase == .resting else { return }
        phase = .paused
    }

    public mutating func resume() {
        guard phase == .paused else { return }
        phase = elapsedFocusSeconds < configuration.focusMinutes * 60 ? .focusing : .resting
    }

    public mutating func stopEarly() {
        guard ![.completed, .stoppedEarly].contains(phase) else { return }
        phase = .stoppedEarly
    }

    /// Records a user-entered check-in without attempting to interpret a
    /// symptom clinically. A higher rating pauses an active timer so the user
    /// can consult their confirmed care plan or a professional before choosing
    /// whether to continue.
    @discardableResult
    public mutating func applyCheckIn(startingRating: Int, currentRating: Int) -> Bool {
        let starting = max(0, min(startingRating, 10))
        let current = max(0, min(currentRating, 10))
        guard isRunning, current > starting else { return false }
        pause()
        return true
    }

    public mutating func tick() {
        switch phase {
        case .focusing:
            elapsedFocusSeconds += 1
            if elapsedFocusSeconds >= configuration.focusMinutes * 60 {
                phase = .resting
            }
        case .resting:
            elapsedRestSeconds += 1
            if elapsedRestSeconds >= configuration.restMinutes * 60 {
                phase = .completed
            }
        case .ready, .paused, .completed, .stoppedEarly:
            break
        }
    }
}

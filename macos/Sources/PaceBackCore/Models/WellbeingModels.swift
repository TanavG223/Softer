import Foundation

/// A closed, non-diagnostic description selected by the person using PaceBack.
/// The app does not infer a need from text, sensors, play, or dwell time.
public enum WellbeingNeedID: String, CaseIterable, Codable, Identifiable, Sendable {
    case tooMuchAtOnce
    case thoughtsMovingFast
    case bodyFeelsTense
    case feelDisconnected
    case needToMove
    case notSure

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tooMuchAtOnce: "Too much at once"
        case .thoughtsMovingFast: "Thoughts moving fast"
        case .bodyFeelsTense: "Body feels tense"
        case .feelDisconnected: "Feel disconnected"
        case .needToMove: "Need to move"
        case .notSure: "Choose for me"
        }
    }

    public var detail: String {
        switch self {
        case .tooMuchAtOnce: "Make the next moment smaller."
        case .thoughtsMovingFast: "Put attention on something outside the thought stream."
        case .bodyFeelsTense: "Try an option that does not require straining."
        case .feelDisconnected: "Reconnect with the room or a person you trust."
        case .needToMove: "Choose a small movement within your usual range."
        case .notSure: "Use the first available neutral option."
        }
    }

    public var systemImage: String {
        switch self {
        case .tooMuchAtOnce: "square.stack.3d.up.fill"
        case .thoughtsMovingFast: "wind"
        case .bodyFeelsTense: "hand.raised.fingers.spread.fill"
        case .feelDisconnected: "person.2.fill"
        case .needToMove: "figure.walk.motion"
        case .notSure: "sparkles"
        }
    }
}

public enum WellbeingModalityID: String, CaseIterable, Codable, Sendable {
    case externalGrounding
    case breathing
    case muscleRelease
    case movement
    case humanConnection
    case interactivePlay
    case lowStimulation
    case practicalPlanning
}

/// A finite catalog. Copy describes optional practices, not promised outcomes.
public enum WellbeingActivityID: String, CaseIterable, Codable, Identifiable, Sendable {
    case orientOutside
    case gentleBreathing
    case muscleRelease
    case comfortableMovement
    case trustedConnection
    case harborPath
    case harborTiles
    case screenOffPause
    case oneSmallStep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .orientOutside: "Notice the room"
        case .gentleBreathing: "Gentle breathing"
        case .muscleRelease: "Soften and release"
        case .comfortableMovement: "Small movement"
        case .trustedConnection: "Reach someone you trust"
        case .harborPath: "Play Harbor Path"
        case .harborTiles: "Play Harbor Tiles"
        case .screenOffPause: "Screen-off pause"
        case .oneSmallStep: "Choose one small step"
        }
    }

    public var shortDetail: String {
        switch self {
        case .orientOutside: "An eyes-open, outside-in noticing exercise."
        case .gentleBreathing: "Comfortable breaths with no holds or required count."
        case .muscleRelease: "Release tension without forcing or straining."
        case .comfortableMovement: "A seated or standing movement within your usual range."
        case .trustedConnection: "Draft a check-in; Softer never sends it automatically."
        case .harborPath: "Guide a lantern home with no score, timer, or losing."
        case .harborTiles: "Fit sea-glass pieces into finite coves with no score or timer."
        case .screenOffPause: "Step away from the screen with no countdown or required return."
        case .oneSmallStep: "Pick one controllable action for the next ten minutes."
        }
    }

    public var durationLabel: String {
        switch self {
        case .orientOutside, .oneSmallStep: "About 1 minute"
        case .gentleBreathing, .muscleRelease, .comfortableMovement: "1–2 minutes"
        case .trustedConnection, .screenOffPause, .harborTiles: "At your pace"
        case .harborPath: "1–3 minutes"
        }
    }

    public var systemImage: String {
        switch self {
        case .orientOutside: "viewfinder"
        case .gentleBreathing: "leaf.fill"
        case .muscleRelease: "hand.raised.fill"
        case .comfortableMovement: "figure.cooldown"
        case .trustedConnection: "message.fill"
        case .harborPath: "point.topleft.down.to.point.bottomright.curvepath"
        case .harborTiles: "square.grid.3x3.fill"
        case .screenOffPause: "display.slash"
        case .oneSmallStep: "checkmark.circle.fill"
        }
    }

    public var modality: WellbeingModalityID {
        switch self {
        case .orientOutside: .externalGrounding
        case .gentleBreathing: .breathing
        case .muscleRelease: .muscleRelease
        case .comfortableMovement: .movement
        case .trustedConnection: .humanConnection
        case .harborPath, .harborTiles: .interactivePlay
        case .screenOffPause: .lowStimulation
        case .oneSmallStep: .practicalPlanning
        }
    }

    public var isGame: Bool { modality == .interactivePlay }

    public var instructions: [String] {
        switch self {
        case .orientOutside:
            ["Keep your eyes open if that feels comfortable.", "Notice three neutral shapes or colors.", "Stop whenever you want."]
        case .gentleBreathing:
            ["Let your breath stay natural.", "Try a slightly longer, comfortable exhale without holding.", "Return to ordinary breathing at any time."]
        case .muscleRelease:
            ["Choose one area such as your hands or shoulders.", "Let that area soften without squeezing first.", "Stop if anything hurts or feels wrong."]
        case .comfortableMovement:
            ["Choose sitting or standing.", "Make one small movement within your usual range.", "Stop for pain, dizziness, or discomfort."]
        case .trustedConnection:
            ["Choose someone you trust.", "Draft a short message asking whether they can check in.", "Review it yourself; Softer does not send messages."]
        case .harborPath:
            ["Follow one clue at a time.", "Guide the lantern to the harbor.", "There is no score or time limit."]
        case .harborTiles:
            ["Move one sea-glass piece at a time.", "Fill the finite cove shapes.", "There is no score, timer, or losing state."]
        case .screenOffPause:
            ["Step away from the display if it is safe to do so.", "Return only when you choose."]
        case .oneSmallStep:
            ["Name one thing you can control in the next ten minutes.", "Make it small enough to begin now.", "Choosing not to continue is also allowed."]
        }
    }

    /// Under-13 profiles are caregiver-operated. Breath and muscle practices
    /// are withheld in this prototype until age-specific review is completed.
    public func isAvailable(for profile: LocalProfile) -> Bool {
        guard RolePolicy.permits(.useGuidedSessions, profile: profile) else { return false }
        switch profile.ageBand {
        case .youngChild0To5:
            return [.orientOutside, .comfortableMovement, .trustedConnection, .screenOffPause, .oneSmallStep]
                .contains(self)
        case .child6To12:
            return self != .gentleBreathing && self != .muscleRelease
        case .teen13To17, .adult18To64, .olderAdult65Plus:
            return true
        }
    }
}

/// The only feedback PaceBack stores after an activity. No free text, score,
/// biometric measurement, or inferred state is accepted by this interface.
public enum WellbeingOutcome: String, CaseIterable, Codable, Identifiable, Sendable {
    case moreSettled
    case same
    case lessSettled
    case skipped

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .moreSettled: "A little more settled"
        case .same: "About the same"
        case .lessSettled: "Less settled"
        case .skipped: "Skip"
        }
    }
}

public struct WellbeingFeedbackEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: Int { sequence }
    public let sequence: Int
    public let needID: WellbeingNeedID
    public let activityID: WellbeingActivityID
    public let outcome: WellbeingOutcome
    public let recordedAt: Date
}

public struct WellbeingPreferenceSignal: Codable, Hashable, Sendable {
    public let targetID: String
    public var score: Double

    public init(targetID: String, score: Double) {
        self.targetID = targetID
        self.score = score.isFinite ? score : 0
    }
}

/// Explicit-feedback-only state stored inside its owning encrypted profile.
public struct WellbeingPersonalizationState: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumFeedbackEvents = 120
    public static let scoreLimit = 0.40
    public static let decayHalfLife: TimeInterval = 30 * 24 * 60 * 60
    public static let lessSettledCooldown: TimeInterval = 24 * 60 * 60
    public static let maximumFutureClockSkew: TimeInterval = 5 * 60

    public let schemaVersion: Int
    public let profileID: UUID
    public let ageBand: AgeBand
    public private(set) var signals: [WellbeingPreferenceSignal]
    public private(set) var feedbackEvents: [WellbeingFeedbackEvent]
    public private(set) var nextFeedbackSequence: Int
    public private(set) var updatedAt: Date

    public init(profileID: UUID, ageBand: AgeBand, now: Date = .now) {
        schemaVersion = Self.currentSchemaVersion
        self.profileID = profileID
        self.ageBand = ageBand
        signals = []
        feedbackEvents = []
        nextFeedbackSequence = 1
        updatedAt = now
    }

    public var isNeutral: Bool { signals.isEmpty && feedbackEvents.isEmpty }

    public func belongs(to profile: LocalProfile, at now: Date = .now) -> Bool {
        let sequences = feedbackEvents.map(\.sequence)
        let retainedSignalKeys = Set(feedbackEvents.map {
            Self.signalKey(needID: $0.needID, activityID: $0.activityID)
        })
        let latestAllowed = now.addingTimeInterval(Self.maximumFutureClockSkew)
        return now.timeIntervalSinceReferenceDate.isFinite
            && updatedAt.timeIntervalSinceReferenceDate.isFinite
            && updatedAt <= latestAllowed
            && schemaVersion == Self.currentSchemaVersion
            && profileID == profile.id
            && ageBand == profile.ageBand
            && nextFeedbackSequence > 0
            && feedbackEvents.count <= Self.maximumFeedbackEvents
            && Set(sequences).count == sequences.count
            && zip(sequences, sequences.dropFirst()).allSatisfy { $0 < $1 }
            && (sequences.last ?? 0) < nextFeedbackSequence
            && feedbackEvents.allSatisfy {
                $0.sequence > 0
                    && $0.recordedAt.timeIntervalSinceReferenceDate.isFinite
                    && $0.recordedAt <= updatedAt
                    && $0.activityID.isAvailable(for: profile)
            }
            && Set(signals.map(\.targetID)).count == signals.count
            && signals.allSatisfy {
                Self.validSignalKeys.contains($0.targetID)
                    && retainedSignalKeys.contains($0.targetID)
                    && $0.score.isFinite
                    && abs($0.score) <= Self.scoreLimit
            }
    }

    public mutating func record(
        needID: WellbeingNeedID,
        activityID: WellbeingActivityID,
        outcome: WellbeingOutcome,
        at now: Date
    ) {
        guard nextFeedbackSequence > 0, nextFeedbackSequence < Int.max else { return }
        applyDecay(at: now)
        let delta: Double
        switch outcome {
        case .moreSettled: delta = 0.12
        case .same: delta = 0
        case .lessSettled: delta = -0.16
        case .skipped: delta = -0.02
        }
        updateSignal(key: Self.signalKey(needID: needID, activityID: activityID), delta: delta)
        feedbackEvents.append(
            WellbeingFeedbackEvent(
                sequence: nextFeedbackSequence,
                needID: needID,
                activityID: activityID,
                outcome: outcome,
                recordedAt: now
            )
        )
        nextFeedbackSequence += 1
        trimFeedbackEventsPreservingCooldownReceipts()
        let retainedKeys = Set(feedbackEvents.map {
            Self.signalKey(needID: $0.needID, activityID: $0.activityID)
        })
        signals.removeAll { !retainedKeys.contains($0.targetID) }
        signals.sort { $0.targetID < $1.targetID }
        updatedAt = max(updatedAt, now)
    }

    public mutating func applyDecay(at now: Date) {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        guard elapsed > 0 else { return }
        let factor = pow(0.5, elapsed / Self.decayHalfLife)
        signals = signals.compactMap { signal in
            let score = signal.score * factor
            guard abs(score) >= 0.0001 else { return nil }
            return WellbeingPreferenceSignal(targetID: signal.targetID, score: score)
        }
        updatedAt = now
    }

    public func score(
        for needID: WellbeingNeedID,
        activityID: WellbeingActivityID,
        at now: Date
    ) -> Double {
        var decayed = self
        decayed.applyDecay(at: now)
        return decayed.signals.first {
            $0.targetID == Self.signalKey(needID: needID, activityID: activityID)
        }?.score ?? 0
    }

    /// A Less-settled receipt pauses only that exact activity for exactly 24h.
    /// A future-dated receipt never creates an indefinite cooldown.
    public func isCoolingDown(_ activityID: WellbeingActivityID, at now: Date) -> Bool {
        guard let last = feedbackEvents.last(where: {
            $0.activityID == activityID && $0.outcome == .lessSettled
        }) else { return false }
        let elapsed = now.timeIntervalSince(last.recordedAt)
        return elapsed >= 0 && elapsed < Self.lessSettledCooldown
    }

    public static func signalKey(
        needID: WellbeingNeedID,
        activityID: WellbeingActivityID
    ) -> String {
        "\(needID.rawValue)|\(activityID.rawValue)"
    }

    private static let validSignalKeys = Set(WellbeingNeedID.allCases.flatMap { need in
        WellbeingActivityID.allCases.map { activity in
            signalKey(needID: need, activityID: activity)
        }
    })

    private mutating func updateSignal(key: String, delta: Double) {
        guard delta != 0 else { return }
        if let index = signals.firstIndex(where: { $0.targetID == key }) {
            signals[index].score = min(
                Self.scoreLimit,
                max(-Self.scoreLimit, signals[index].score + delta)
            )
        } else {
            signals.append(
                WellbeingPreferenceSignal(
                    targetID: key,
                    score: min(Self.scoreLimit, max(-Self.scoreLimit, delta))
                )
            )
        }
    }

    private mutating func trimFeedbackEventsPreservingCooldownReceipts() {
        let excess = feedbackEvents.count - Self.maximumFeedbackEvents
        guard excess > 0 else { return }
        let protectedSequences = Set(WellbeingActivityID.allCases.compactMap { activityID in
            feedbackEvents.last(where: {
                $0.activityID == activityID && $0.outcome == .lessSettled
            })?.sequence
        })
        let evictedSequences = Set(
            feedbackEvents.lazy
                .filter { !protectedSequences.contains($0.sequence) }
                .prefix(excess)
                .map(\.sequence)
        )
        feedbackEvents.removeAll { evictedSequences.contains($0.sequence) }
    }
}

public struct WellbeingRecommendation: Equatable, Sendable {
    public let needID: WellbeingNeedID
    public let activityID: WellbeingActivityID
    public let reason: String
    public let learnedFromExplicitFeedback: Bool
    public let alternatives: [WellbeingActivityID]
    public let coolingDownActivityIDs: Set<WellbeingActivityID>
    public let hasEligibleActivities: Bool
    public let allEligibleActivitiesCoolingDown: Bool

    public var canStart: Bool { hasEligibleActivities && !allEligibleActivitiesCoolingDown }
}

public struct WellbeingSession: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let profileID: UUID
    public let needID: WellbeingNeedID
    public let activityID: WellbeingActivityID
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        needID: WellbeingNeedID,
        activityID: WellbeingActivityID,
        startedAt: Date = .now
    ) {
        self.id = id
        self.profileID = profileID
        self.needID = needID
        self.activityID = activityID
        self.startedAt = startedAt
    }
}

public enum WellbeingRecommender {
    public static func recommendation(
        for needID: WellbeingNeedID,
        profile: LocalProfile,
        state: WellbeingPersonalizationState,
        at now: Date = .now
    ) -> WellbeingRecommendation {
        let baseline = baselineOrder(for: needID).filter { $0.isAvailable(for: profile) }
        let ranked = baseline.enumerated().sorted { left, right in
            let leftCooling = state.isCoolingDown(left.element, at: now)
            let rightCooling = state.isCoolingDown(right.element, at: now)
            if leftCooling != rightCooling { return !leftCooling }
            let leftScore = state.score(for: needID, activityID: left.element, at: now)
            let rightScore = state.score(for: needID, activityID: right.element, at: now)
            if leftScore != rightScore { return leftScore > rightScore }
            return left.offset < right.offset
        }.map(\.element)

        let cooling = Set(baseline.filter { state.isCoolingDown($0, at: now) })
        let availableNow = ranked.filter { !cooling.contains($0) }
        let allCooling = !baseline.isEmpty && availableNow.isEmpty
        let activity = availableNow.first ?? ranked.first ?? .orientOutside
        let learned = state.score(for: needID, activityID: activity, at: now) >= 0.02
        let reason: String
        if baseline.isEmpty {
            reason = "No guided activity is available for this profile’s current age and role."
        } else if allCooling {
            reason = "Every available activity is paused after an explicit Less settled check-out. Softer will not automatically choose one during its 24-hour cooldown."
        } else if learned {
            reason = "This matches your selection, and your explicit check-outs previously favored it. No passive behavior was used."
        } else if profile.ageBand.isUnder13 {
            reason = "This is a short caregiver-led option for your selection. Softer does not infer or score a child’s feelings."
        } else {
            reason = "This is the first fixed option for your selection. It is optional and is not a treatment recommendation."
        }

        var modalities: Set<WellbeingModalityID> = [activity.modality]
        let alternatives = availableNow.dropFirst().filter { candidate in
            modalities.insert(candidate.modality).inserted
        }
        return WellbeingRecommendation(
            needID: needID,
            activityID: activity,
            reason: reason,
            learnedFromExplicitFeedback: learned,
            alternatives: Array(alternatives.prefix(3)),
            coolingDownActivityIDs: cooling,
            hasEligibleActivities: !baseline.isEmpty,
            allEligibleActivitiesCoolingDown: allCooling
        )
    }

    public static func baselineOrder(for needID: WellbeingNeedID) -> [WellbeingActivityID] {
        switch needID {
        case .tooMuchAtOnce:
            [.orientOutside, .screenOffPause, .oneSmallStep, .gentleBreathing, .harborPath, .trustedConnection, .harborTiles, .muscleRelease, .comfortableMovement]
        case .thoughtsMovingFast:
            [.orientOutside, .harborTiles, .screenOffPause, .harborPath, .gentleBreathing, .oneSmallStep, .trustedConnection, .comfortableMovement, .muscleRelease]
        case .bodyFeelsTense:
            [.muscleRelease, .comfortableMovement, .gentleBreathing, .orientOutside, .screenOffPause, .trustedConnection, .harborPath, .oneSmallStep, .harborTiles]
        case .feelDisconnected:
            [.trustedConnection, .orientOutside, .harborPath, .screenOffPause, .comfortableMovement, .oneSmallStep, .gentleBreathing, .harborTiles, .muscleRelease]
        case .needToMove:
            [.comfortableMovement, .harborTiles, .orientOutside, .screenOffPause, .harborPath, .trustedConnection, .gentleBreathing, .oneSmallStep, .muscleRelease]
        case .notSure:
            [.orientOutside, .screenOffPause, .harborPath, .gentleBreathing, .oneSmallStep, .trustedConnection, .harborTiles, .comfortableMovement, .muscleRelease]
        }
    }
}

/// Static destinations only. Opening support never creates feedback or alters
/// personalization, and PaceBack does not monitor whether a route is used.
public enum SupportRoute: String, CaseIterable, Codable, Identifiable, Sendable {
    case immediateDanger
    case call988
    case text988
    case chat988
    case internationalDirectory
    case trustedPerson
    case professionalCare

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .immediateDanger: "Call 911 · U.S. only"
        case .call988: "Call 988 · U.S. only"
        case .text988: "Text 988 · U.S. only"
        case .chat988: "Chat with 988 · U.S. only"
        case .internationalDirectory: "Find support outside the U.S."
        case .trustedPerson: "Contact someone you trust"
        case .professionalCare: "Contact a licensed professional"
        }
    }

    public var detail: String {
        switch self {
        case .immediateDanger: "If there is immediate danger, call your local emergency number now."
        case .call988, .text988, .chat988: "U.S. Suicide & Crisis Lifeline support."
        case .internationalDirectory: "Open a country-by-country crisis support directory."
        case .trustedPerson: "Opens Messages so you can choose and contact a trusted person yourself. Softer does not send messages."
        case .professionalCare: "Opens Contacts so you can choose contact information you already trust for a clinician or counselor."
        }
    }

    public var destinationURL: URL? {
        switch self {
        case .immediateDanger: URL(string: "tel:911")
        case .call988: URL(string: "tel:988")
        case .text988: URL(string: "sms:988")
        case .chat988: URL(string: "https://988lifeline.org/chat/")
        case .internationalDirectory: URL(string: "https://findahelpline.com/")
        case .trustedPerson, .professionalCare: nil
        }
    }

    public var requiresConfirmation: Bool {
        true
    }

    public static let boundaryNotice =
        "Softer is not a crisis service, does not monitor you, and cannot contact help for you."
}

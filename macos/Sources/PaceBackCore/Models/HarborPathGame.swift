import Foundation

/// Closed, content-free identifiers for Harbor Path's three sensory prompts.
public enum QuietHarborPromptID: String, CaseIterable, Codable, Hashable, Sendable {
    case steadyObject
    case supportedSurface
    case familiarSound
}

public enum HarborPathUnavailableReason: String, Equatable, Sendable {
    case youngChildScreenOffOnly
    case invalidCheckpointCount
}

public enum HarborPathPresentation: String, Equatable, Sendable {
    case child
    case teen
    case adult
    case olderAdult
}

public enum HarborPathActionID: String, CaseIterable, Equatable, Sendable {
    case placeHarborItem
    case skipCheckpoint
    case stop
}

public enum HarborPathCheckpointResultID: String, Equatable, Sendable {
    case waypointPlaced
    case skipped
}

public enum HarborPathItemID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case shoreLight
    case dockPost
    case harborBell

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .shoreLight: "lightbulb.fill"
        case .dockPost: "circle.fill"
        case .harborBell: "bell.fill"
        }
    }

    public var accessibilityTitle: String {
        switch self {
        case .shoreLight: "Shore light"
        case .dockPost: "Dock post"
        case .harborBell: "Harbor bell"
        }
    }
}

public enum HarborPathResolutionID: String, Equatable, Sendable {
    case active
    case pathComplete
    case skippedComplete
    case stoppedComplete

    public var isComplete: Bool { self != .active }
}

public struct HarborPathCheckpointResult: Equatable, Sendable {
    public let checkpointID: QuietHarborPromptID
    public let resultID: HarborPathCheckpointResultID
}

public struct HarborPathGameSummary: Equatable, Sendable {
    public let resolutionID: HarborPathResolutionID
    public let checkpointResults: [HarborPathCheckpointResult]

    /// Every cue actually displayed, including the current cue when the user
    /// stops before placing its harbor item.
    public let shownCheckpointIDs: [QuietHarborPromptID]
}

public enum HarborPathTransition: Equatable, Sendable {
    case advanced(to: QuietHarborPromptID)
    case ended(HarborPathResolutionID)
    case ignored
}

public enum HarborPathPreparation: Equatable, Sendable {
    case unavailable(HarborPathUnavailableReason)
    case ready(HarborPathGame)
}

/// Pure, finite, session-only state for Harbor Path.
///
/// This type is intentionally not Codable. It contains only closed IDs and
/// bounded counters—never mood, symptom, free text, timing, score, streak, or
/// reward data.
public struct HarborPathGame: Equatable, Sendable {
    public static let minimumCheckpointCount = 1
    public static let maximumCheckpointCount = 3

    public let ageBand: AgeBand
    public let presentation: HarborPathPresentation
    public let checkpointIDs: [QuietHarborPromptID]
    public private(set) var currentIndex: Int
    public private(set) var checkpointResults: [HarborPathCheckpointResult]
    public private(set) var resolutionID: HarborPathResolutionID

    public static func prepare(
        ageBand: AgeBand,
        checkpointCount: Int,
        orderedCheckpointIDs: [QuietHarborPromptID] = QuietHarborPromptID.allCases
    ) -> HarborPathPreparation {
        guard ageBand != .youngChild0To5 else {
            return .unavailable(.youngChildScreenOffOnly)
        }
        guard (minimumCheckpointCount...maximumCheckpointCount).contains(checkpointCount) else {
            return .unavailable(.invalidCheckpointCount)
        }

        var seen: Set<QuietHarborPromptID> = []
        let normalizedOrder = (orderedCheckpointIDs + QuietHarborPromptID.allCases).filter {
            seen.insert($0).inserted
        }

        return .ready(
            HarborPathGame(
                ageBand: ageBand,
                presentation: presentation(for: ageBand),
                checkpointIDs: Array(normalizedOrder.prefix(checkpointCount)),
                currentIndex: 0,
                checkpointResults: [],
                resolutionID: .active
            )
        )
    }

    public var isActive: Bool { resolutionID == .active }

    public var currentCheckpointID: QuietHarborPromptID? {
        guard isActive, checkpointIDs.indices.contains(currentIndex) else { return nil }
        return checkpointIDs[currentIndex]
    }

    public var currentCheckpointNumber: Int? {
        currentCheckpointID == nil ? nil : currentIndex + 1
    }

    public var availableActionIDs: [HarborPathActionID] {
        isActive ? [.placeHarborItem, .skipCheckpoint, .stop] : []
    }

    public var placedItemIDs: [HarborPathItemID] {
        checkpointResults.compactMap { result in
            guard result.resultID == .waypointPlaced else { return nil }
            return result.checkpointID.harborPathItemID
        }
    }

    public var summary: HarborPathGameSummary {
        HarborPathGameSummary(
            resolutionID: resolutionID,
            checkpointResults: checkpointResults,
            shownCheckpointIDs: Array(
                checkpointIDs.prefix(min(checkpointIDs.count, currentIndex + 1))
            )
        )
    }

    public mutating func send(_ actionID: HarborPathActionID) -> HarborPathTransition {
        guard isActive, let checkpointID = currentCheckpointID else { return .ignored }

        switch actionID {
        case .stop:
            resolutionID = .stoppedComplete
            return .ended(.stoppedComplete)
        case .placeHarborItem:
            checkpointResults.append(
                HarborPathCheckpointResult(
                    checkpointID: checkpointID,
                    resultID: .waypointPlaced
                )
            )
        case .skipCheckpoint:
            checkpointResults.append(
                HarborPathCheckpointResult(
                    checkpointID: checkpointID,
                    resultID: .skipped
                )
            )
            resolutionID = .skippedComplete
            return .ended(.skippedComplete)
        }

        currentIndex += 1
        if let nextCheckpointID = currentCheckpointID {
            return .advanced(to: nextCheckpointID)
        }
        resolutionID = .pathComplete
        return .ended(.pathComplete)
    }

    private static func presentation(for ageBand: AgeBand) -> HarborPathPresentation {
        switch ageBand {
        case .youngChild0To5, .child6To12: .child
        case .teen13To17: .teen
        case .adult18To64: .adult
        case .olderAdult65Plus: .olderAdult
        }
    }
}

public struct HarborPathCheckpointCopy: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let actionTitle: String
}

public enum HarborPathCopy {
    public static let productLabel = "Harbor Path · optional game"
    public static let promise = "A tiny game for noticing what is already around you. It may or may not feel helpful. Stop anytime."
    public static let objective = "Guide the lantern home through one to three static waypoints."
    public static let noCompetition = "No score, timer, streak, failure, or reward. Skipping or stopping counts as complete."
    public static let careBoundary = "This exact low-stimulation game has not been clinically validated. It is optional distraction—not treatment or proof that a person is calm."
    public static let skipped = "Skipped. Leaving counts as complete here."
    public static let stopped = "Enough for now. Stopping counts as complete here."
    public static let completed = "The lantern reached home. Nothing was scored."
}

public extension QuietHarborPromptID {
    var harborPathItemID: HarborPathItemID {
        switch self {
        case .steadyObject: .shoreLight
        case .supportedSurface: .dockPost
        case .familiarSound: .harborBell
        }
    }

    func harborPathCopy(for presentation: HarborPathPresentation) -> HarborPathCheckpointCopy {
        switch (self, presentation) {
        case (.steadyObject, .child):
            HarborPathCheckpointCopy(
                title: "Find one steady thing together",
                detail: "A caregiver operates this game and can offer one nearby color, shape, or object. One quick look is enough.",
                actionTitle: "We found one · place the light"
            )
        case (.supportedSurface, .child):
            HarborPathCheckpointCopy(
                title: "Notice support together",
                detail: "A caregiver operates this game and can name a chair, bed, floor, or another steady surface.",
                actionTitle: "We noticed one · place the post"
            )
        case (.familiarSound, .child):
            HarborPathCheckpointCopy(
                title: "Notice one familiar sound together",
                detail: "A caregiver operates this game and can quietly offer one sound. If sound feels like too much, skip this one.",
                actionTitle: "We noticed one · place the bell"
            )
        case (.steadyObject, .teen), (.steadyObject, .adult), (.steadyObject, .olderAdult):
            HarborPathCheckpointCopy(
                title: "Notice one steady thing nearby",
                detail: "Choose a color, shape, or object. Looking briefly is enough.",
                actionTitle: "Place the shore light"
            )
        case (.supportedSurface, .teen), (.supportedSurface, .adult), (.supportedSurface, .olderAdult):
            HarborPathCheckpointCopy(
                title: "Notice one supported surface",
                detail: "A chair, bed, floor, or another surface can count.",
                actionTitle: "Place the dock post"
            )
        case (.familiarSound, .teen), (.familiarSound, .adult), (.familiarSound, .olderAdult):
            HarborPathCheckpointCopy(
                title: "Notice one quiet or familiar sound",
                detail: "Choose one, or skip if sound feels like too much.",
                actionTitle: "Place the harbor bell"
            )
        }
    }
}

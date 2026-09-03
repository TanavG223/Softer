import Foundation

public enum HarborTilesUnavailableReason: String, Equatable, Sendable {
    case youngChildScreenOffOnly
    case invalidConfiguration
}

public enum HarborTilesPresentation: String, Equatable, Sendable {
    case child
    case teen
    case adult
    case olderAdult
}

public enum HarborTilesResolutionID: String, Equatable, Sendable {
    case active
    case completed
    case skipped
    case stopped

    public var isComplete: Bool { self != .active }
}

public struct HarborTilesCell: Hashable, Identifiable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public var id: String { "r\(row)c\(column)" }

    static func + (left: HarborTilesCell, right: HarborTilesCell) -> HarborTilesCell {
        HarborTilesCell(row: left.row + right.row, column: left.column + right.column)
    }
}

public enum HarborTilesPieceID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case threeAcross
    case threeDown
    case cornerLeft
    case cornerRight
    case square
    case tee

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .threeAcross: "Three across"
        case .threeDown: "Three down"
        case .cornerLeft: "Left cove"
        case .cornerRight: "Right cove"
        case .square: "Four-tile window"
        case .tee: "Four-tile beacon"
        }
    }

    public var symbol: String {
        switch self {
        case .threeAcross: "rectangle.split.3x1.fill"
        case .threeDown: "rectangle.split.1x2.fill"
        case .cornerLeft, .cornerRight: "square.3.layers.3d.down.left"
        case .square: "square.grid.2x2.fill"
        case .tee: "t.square.fill"
        }
    }

    public var offsets: [HarborTilesCell] {
        switch self {
        case .threeAcross:
            [Self.cell(0, 0), Self.cell(0, 1), Self.cell(0, 2)]
        case .threeDown:
            [Self.cell(0, 0), Self.cell(1, 0), Self.cell(2, 0)]
        case .cornerLeft:
            [Self.cell(0, 0), Self.cell(1, 0), Self.cell(1, 1)]
        case .cornerRight:
            [Self.cell(0, 0), Self.cell(0, 1), Self.cell(1, 1)]
        case .square:
            [Self.cell(0, 0), Self.cell(0, 1), Self.cell(1, 0), Self.cell(1, 1)]
        case .tee:
            [Self.cell(0, 0), Self.cell(0, 1), Self.cell(0, 2), Self.cell(1, 1)]
        }
    }

    public var cellCount: Int { offsets.count }

    private static func cell(_ row: Int, _ column: Int) -> HarborTilesCell {
        HarborTilesCell(row: row, column: column)
    }
}

public struct HarborTilesCove: Equatable, Sendable {
    public let id: Int
    public let title: String
    public let targetCells: Set<HarborTilesCell>
    public let pieceIDs: [HarborTilesPieceID]

    public init(
        id: Int,
        title: String,
        targetCells: Set<HarborTilesCell>,
        pieceIDs: [HarborTilesPieceID]
    ) {
        self.id = id
        self.title = title
        self.targetCells = targetCells
        self.pieceIDs = pieceIDs
    }
}

public struct HarborTilesPlacement: Equatable, Sendable {
    public let coveIndex: Int
    public let pieceID: HarborTilesPieceID
    public let anchor: HarborTilesCell
    public let occupiedCells: Set<HarborTilesCell>
}

public struct HarborTilesGameSummary: Equatable, Sendable {
    public let resolutionID: HarborTilesResolutionID
    public let placementCount: Int
    public let completedCoveCount: Int
}

public enum HarborTilesRejection: String, Equatable, Sendable {
    case gameEnded
    case coveNeedsAdvance
    case pieceUnavailable
    case destinationUnavailable
    case noMoveToUndo
}

public enum HarborTilesTransition: Equatable, Sendable {
    case selected(HarborTilesPieceID)
    case placed(HarborTilesPlacement)
    case coveCompleted(coveNumber: Int)
    case advanced(coveNumber: Int)
    case undone(HarborTilesPieceID)
    case ended(HarborTilesResolutionID)
    case rejected(HarborTilesRejection)
}

public enum HarborTilesPreparation: Equatable, Sendable {
    case unavailable(HarborTilesUnavailableReason)
    case ready(HarborTilesGame)
}

/// A finite, session-only spatial-fitting game.
///
/// Every accepted move leaves at least one complete tiling for the remaining
/// pieces. This state is deliberately not Codable and has no score, timer,
/// streak, failure state, or behavior-derived difficulty.
public struct HarborTilesGame: Equatable, Sendable {
    public static let boardSize = 4
    public static let coveCount = 3
    public static let placementsPerCove = 3
    public static let totalPlacementCount = coveCount * placementsPerCove

    public let ageBand: AgeBand
    public let presentation: HarborTilesPresentation
    public let coves: [HarborTilesCove]

    public private(set) var currentCoveIndex: Int
    public private(set) var occupiedCells: Set<HarborTilesCell>
    public private(set) var placedPieceIDs: Set<HarborTilesPieceID>
    public private(set) var placementHistory: [HarborTilesPlacement]
    public private(set) var selectedPieceID: HarborTilesPieceID?
    public private(set) var resolutionID: HarborTilesResolutionID

    public static let standardCoves: [HarborTilesCove] = [
        HarborTilesCove(
            id: 0,
            title: "Sheltered cove",
            targetCells: cells([
                (0, 0), (0, 1), (0, 2),
                (1, 0), (1, 2), (1, 3),
                (2, 0), (2, 1), (2, 2), (2, 3)
            ]),
            pieceIDs: [.threeAcross, .cornerLeft, .square]
        ),
        HarborTilesCove(
            id: 1,
            title: "Open-water cove",
            targetCells: cells([
                (0, 0), (0, 1), (0, 2), (0, 3),
                (1, 0), (1, 2),
                (2, 0), (2, 1), (2, 2), (2, 3)
            ]),
            pieceIDs: [.threeDown, .threeAcross, .tee]
        ),
        HarborTilesCove(
            id: 2,
            title: "Lantern cove",
            targetCells: cells([
                (0, 0), (0, 1), (0, 2), (0, 3),
                (1, 0), (1, 1), (1, 3),
                (2, 1), (2, 2), (2, 3)
            ]),
            pieceIDs: [.square, .cornerRight, .threeAcross]
        )
    ]

    public static func prepare(
        ageBand: AgeBand,
        coves: [HarborTilesCove] = standardCoves
    ) -> HarborTilesPreparation {
        guard ageBand != .youngChild0To5 else {
            return .unavailable(.youngChildScreenOffOnly)
        }
        guard configurationIsValid(coves) else {
            return .unavailable(.invalidConfiguration)
        }

        var game = HarborTilesGame(
            ageBand: ageBand,
            presentation: presentation(for: ageBand),
            coves: coves,
            currentCoveIndex: 0,
            occupiedCells: [],
            placedPieceIDs: [],
            placementHistory: [],
            selectedPieceID: nil,
            resolutionID: .active
        )
        game.selectFirstAvailablePiece()
        return .ready(game)
    }

    public var isActive: Bool { resolutionID == .active }

    public var currentCove: HarborTilesCove? {
        guard coves.indices.contains(currentCoveIndex) else { return nil }
        return coves[currentCoveIndex]
    }

    public var currentCoveNumber: Int { min(coves.count, currentCoveIndex + 1) }

    public var completedCoveCount: Int {
        if resolutionID == .completed { return coves.count }
        if currentCoveIsComplete { return currentCoveIndex + 1 }
        return currentCoveIndex
    }

    public var placementCount: Int { placementHistory.count }

    public var coveNeedsAdvance: Bool {
        guard isActive else { return false }
        return currentCoveIsComplete && currentCoveIndex < coves.count - 1
    }

    private var currentCoveIsComplete: Bool {
        guard let currentCove else { return false }
        return placedPieceIDs.count == currentCove.pieceIDs.count
    }

    public var remainingPieceIDs: [HarborTilesPieceID] {
        guard let currentCove else { return [] }
        return currentCove.pieceIDs.filter { !placedPieceIDs.contains($0) }
    }

    public var summary: HarborTilesGameSummary {
        HarborTilesGameSummary(
            resolutionID: resolutionID,
            placementCount: placementCount,
            completedCoveCount: completedCoveCount
        )
    }

    public func cells(
        for pieceID: HarborTilesPieceID,
        at anchor: HarborTilesCell
    ) -> Set<HarborTilesCell> {
        Self.pieceCells(for: pieceID, at: anchor)
    }

    public func validAnchors(for pieceID: HarborTilesPieceID) -> [HarborTilesCell] {
        guard isActive,
              !coveNeedsAdvance,
              remainingPieceIDs.contains(pieceID),
              let cove = currentCove else {
            return []
        }

        let remaining = remainingPieceIDs.filter { $0 != pieceID }
        return Self.rawAnchors(
            for: pieceID,
            occupied: occupiedCells,
            target: cove.targetCells
        ).filter { anchor in
            let nextOccupied = occupiedCells.union(cells(for: pieceID, at: anchor))
            return Self.canComplete(
                remainingPieceIDs: remaining,
                occupied: nextOccupied,
                cove: cove
            )
        }
    }

    public func hint() -> (pieceID: HarborTilesPieceID, anchor: HarborTilesCell)? {
        let candidates: [HarborTilesPieceID]
        if let selectedPieceID {
            candidates = [selectedPieceID] + remainingPieceIDs.filter { $0 != selectedPieceID }
        } else {
            candidates = remainingPieceIDs
        }
        for pieceID in candidates {
            if let anchor = validAnchors(for: pieceID).first {
                return (pieceID, anchor)
            }
        }
        return nil
    }

    public mutating func select(_ pieceID: HarborTilesPieceID) -> HarborTilesTransition {
        guard isActive else { return .rejected(.gameEnded) }
        guard !coveNeedsAdvance else { return .rejected(.coveNeedsAdvance) }
        guard remainingPieceIDs.contains(pieceID), !validAnchors(for: pieceID).isEmpty else {
            return .rejected(.pieceUnavailable)
        }
        selectedPieceID = pieceID
        return .selected(pieceID)
    }

    public mutating func place(at anchor: HarborTilesCell) -> HarborTilesTransition {
        guard isActive else { return .rejected(.gameEnded) }
        guard !coveNeedsAdvance else { return .rejected(.coveNeedsAdvance) }
        guard let pieceID = selectedPieceID,
              validAnchors(for: pieceID).contains(anchor) else {
            return .rejected(.destinationUnavailable)
        }

        let placement = HarborTilesPlacement(
            coveIndex: currentCoveIndex,
            pieceID: pieceID,
            anchor: anchor,
            occupiedCells: cells(for: pieceID, at: anchor)
        )
        occupiedCells.formUnion(placement.occupiedCells)
        placedPieceIDs.insert(pieceID)
        placementHistory.append(placement)

        guard let currentCove else { return .rejected(.destinationUnavailable) }
        if placedPieceIDs.count == currentCove.pieceIDs.count {
            selectedPieceID = nil
            if currentCoveIndex == coves.count - 1 {
                resolutionID = .completed
                return .ended(.completed)
            }
            return .coveCompleted(coveNumber: currentCoveNumber)
        }

        selectFirstAvailablePiece()
        return .placed(placement)
    }

    /// Keyboard/tap-friendly atomic placement. An invalid destination does not
    /// change the selected tray piece.
    public mutating func place(
        pieceID: HarborTilesPieceID,
        at anchor: HarborTilesCell
    ) -> HarborTilesTransition {
        guard validAnchors(for: pieceID).contains(anchor) else {
            return .rejected(.destinationUnavailable)
        }
        selectedPieceID = pieceID
        return place(at: anchor)
    }

    public mutating func advanceCove() -> HarborTilesTransition {
        guard isActive else { return .rejected(.gameEnded) }
        guard coveNeedsAdvance else { return .rejected(.coveNeedsAdvance) }
        currentCoveIndex += 1
        occupiedCells = []
        placedPieceIDs = []
        selectFirstAvailablePiece()
        return .advanced(coveNumber: currentCoveNumber)
    }

    public mutating func undo() -> HarborTilesTransition {
        guard isActive else { return .rejected(.gameEnded) }
        guard let last = placementHistory.last, last.coveIndex == currentCoveIndex else {
            return .rejected(.noMoveToUndo)
        }
        placementHistory.removeLast()
        occupiedCells.subtract(last.occupiedCells)
        placedPieceIDs.remove(last.pieceID)
        selectedPieceID = last.pieceID
        return .undone(last.pieceID)
    }

    public mutating func stop() -> HarborTilesTransition {
        guard isActive else { return .rejected(.gameEnded) }
        resolutionID = .stopped
        selectedPieceID = nil
        return .ended(.stopped)
    }

    public mutating func skip() -> HarborTilesTransition {
        guard isActive else { return .rejected(.gameEnded) }
        resolutionID = .skipped
        selectedPieceID = nil
        return .ended(.skipped)
    }

    private mutating func selectFirstAvailablePiece() {
        selectedPieceID = remainingPieceIDs.first { !validAnchors(for: $0).isEmpty }
    }

    private static func canComplete(
        remainingPieceIDs: [HarborTilesPieceID],
        occupied: Set<HarborTilesCell>,
        cove: HarborTilesCove
    ) -> Bool {
        guard !remainingPieceIDs.isEmpty else { return occupied == cove.targetCells }

        let candidates = remainingPieceIDs.map { pieceID in
            (
                pieceID,
                rawAnchors(for: pieceID, occupied: occupied, target: cove.targetCells)
            )
        }
        guard let next = candidates.min(by: { $0.1.count < $1.1.count }),
              !next.1.isEmpty else {
            return false
        }
        let rest = remainingPieceIDs.filter { $0 != next.0 }
        return next.1.contains { anchor in
            let nextOccupied = occupied.union(pieceCells(for: next.0, at: anchor))
            return canComplete(
                remainingPieceIDs: rest,
                occupied: nextOccupied,
                cove: cove
            )
        }
    }

    private static func rawAnchors(
        for pieceID: HarborTilesPieceID,
        occupied: Set<HarborTilesCell>,
        target: Set<HarborTilesCell>
    ) -> [HarborTilesCell] {
        var anchors: [HarborTilesCell] = []
        for row in 0..<boardSize {
            for column in 0..<boardSize {
                let anchor = HarborTilesCell(row: row, column: column)
                let candidate = pieceCells(for: pieceID, at: anchor)
                guard candidate.count == pieceID.cellCount,
                      candidate.isSubset(of: target),
                      candidate.isDisjoint(with: occupied) else {
                    continue
                }
                anchors.append(anchor)
            }
        }
        return anchors
    }

    private static func pieceCells(
        for pieceID: HarborTilesPieceID,
        at anchor: HarborTilesCell
    ) -> Set<HarborTilesCell> {
        Set(pieceID.offsets.map { anchor + $0 })
    }

    private static func configurationIsValid(_ coves: [HarborTilesCove]) -> Bool {
        guard coves.count == coveCount else { return false }
        for cove in coves {
            guard cove.pieceIDs.count == placementsPerCove,
                  Set(cove.pieceIDs).count == cove.pieceIDs.count,
                  cove.targetCells.count == cove.pieceIDs.reduce(0, { $0 + $1.cellCount }),
                  cove.targetCells.allSatisfy({ cell in
                      (0..<boardSize).contains(cell.row)
                          && (0..<boardSize).contains(cell.column)
                  }),
                  canComplete(
                      remainingPieceIDs: cove.pieceIDs,
                      occupied: [],
                      cove: cove
                  ) else {
                return false
            }
        }
        return true
    }

    private static func presentation(for ageBand: AgeBand) -> HarborTilesPresentation {
        switch ageBand {
        case .youngChild0To5, .child6To12: .child
        case .teen13To17: .teen
        case .adult18To64: .adult
        case .olderAdult65Plus: .olderAdult
        }
    }

    private static func cells(_ values: [(Int, Int)]) -> Set<HarborTilesCell> {
        Set(values.map { HarborTilesCell(row: $0.0, column: $0.1) })
    }
}

public enum HarborTilesCopy {
    public static let productLabel = "Harbor Tiles · optional game"
    public static let promise = "Fit nine sea-glass pieces into three small coves. There is no score, no timer, and no losing. Stop or leave anytime."
    public static let focusBoundary = "This may offer a brief change of focus. It may not feel helpful."
    public static let careBoundary = "This exact game has not been clinically validated. It is optional play—not treatment, a mental-health test, or proof that someone is calm."
    public static let completion = "The three harbor lights are on. Nothing was scored."

    public static func initialInstruction(for ageBand: AgeBand) -> String {
        ageBand.isUnder13
            ? "A caregiver operates this game. Together, choose a sea-glass piece, then choose an outlined fit."
            : "Choose a sea-glass piece, then choose an outlined fit."
    }

    public static func selectionInstruction(
        pieceTitle: String,
        for ageBand: AgeBand
    ) -> String {
        ageBand.isUnder13
            ? "\(pieceTitle) selected. Together, choose an outlined plus or use Place selected piece."
            : "\(pieceTitle) selected. Choose an outlined plus or use Place selected piece."
    }
}

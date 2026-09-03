import SwiftUI

/// Keyboard- and VoiceOver-operable Harbor Tiles board. The parent owns the
/// session boundary and receives only a closed, bounded summary.
public struct HarborTilesGameView: View {
    @State private var game: HarborTilesGame
    @State private var lastMessage: String
    @State private var hintedAnchor: HarborTilesCell?

    private let onEnd: (HarborTilesGameSummary) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(
        game: HarborTilesGame,
        onEnd: @escaping (HarborTilesGameSummary) -> Void
    ) {
        _game = State(initialValue: game)
        _lastMessage = State(initialValue: HarborTilesCopy.initialInstruction(for: game.ageBand))
        self.onEnd = onEnd
    }

    public var body: some View {
        ZStack {
            PaceBackCanvasBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        gameHeader

                        if game.resolutionID == .completed {
                            completionCard
                        } else if game.coveNeedsAdvance {
                            coveCompleteCard
                        } else {
                            activeGame
                        }

                        Text(HarborTilesCopy.careBoundary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }

                if game.isActive {
                    Divider()
                    persistentExitControls
                }
            }
        }
        .frame(minWidth: 660, minHeight: 650)
        .navigationTitle("Harbor Tiles")
    }

    private var gameHeader: some View {
        PaceBackCard(style: .quiet) {
            HStack(alignment: .top, spacing: 16) {
                beaconStrip
                VStack(alignment: .leading, spacing: 6) {
                    Text("OPTIONAL FOCUS GAME")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(PaceBackDesign.accent)
                    Text("Harbor Tiles")
                        .font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(HarborTilesCopy.promise)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if game.ageBand == .child6To12 {
                        Label("Caregiver-operated for ages 6–12", systemImage: "person.2.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(PaceBackDesign.accent)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var activeGame: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusCard
            pieceTray
            boardCard
            placeSelectedButton
            utilityControls
        }
    }

    private var statusCard: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 7) {
                Text(
                    "COVE \(game.currentCoveNumber) OF \(game.coves.count) · "
                        + "PIECE \(game.placementCount + 1) OF \(HarborTilesGame.totalPlacementCount)"
                )
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PaceBackDesign.accent)

                Text(game.currentCove?.title ?? "Harbor cove")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text(lastMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Game status. \(lastMessage)")
                    .accessibilityIdentifier("harborTiles.turnStatus")

                Text("No score · no timer · no losing")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pieceTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(game.ageBand == .child6To12 ? "Choose one piece together" : "Choose one piece")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { pieceButtons }
                VStack(spacing: 10) { pieceButtons }
            }
        }
    }

    @ViewBuilder
    private var pieceButtons: some View {
        ForEach(Array(game.remainingPieceIDs.enumerated()), id: \.element.id) { index, pieceID in
            Button {
                select(pieceID)
            } label: {
                HStack(spacing: 10) {
                    HarborTilesPiecePreview(pieceID: pieceID, cellSize: 14)
                        .frame(width: 58, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pieceID.title)
                            .font(.callout.weight(.semibold))
                        Text("\(pieceID.cellCount) tiles · key \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(
                    game.selectedPieceID == pieceID
                        ? PaceBackDesign.calmBlue.opacity(0.16)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            game.selectedPieceID == pieceID
                                ? PaceBackDesign.calmBlue
                                : Color.secondary.opacity(0.22),
                            lineWidth: game.selectedPieceID == pieceID ? 2 : 1
                        )
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(
                KeyEquivalent(Character(String(index + 1))),
                modifiers: []
            )
            .accessibilityLabel("\(pieceID.title), \(pieceID.cellCount) tiles")
            .accessibilityValue(game.selectedPieceID == pieceID ? "Selected" : "Not selected")
            .accessibilityHint("Selects this piece. Choose an outlined board position, press Return, or drag it onto the cove.")
            .accessibilityAddTraits(game.selectedPieceID == pieceID ? .isSelected : [])
            .accessibilityIdentifier("harborTiles.piece.\(pieceID.rawValue)")
            .draggable(pieceID.rawValue) {
                HarborTilesPiecePreview(pieceID: pieceID, cellSize: 18)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Dragging \(pieceID.title)")
            }
        }
    }

    private var boardCard: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Cove board", systemImage: "square.grid.3x3")
                        .font(.headline)
                    Spacer()
                    Text("Outlined + = available fit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HarborTilesBoard(
                    game: game,
                    hintedAnchor: hintedAnchor,
                    contrast: contrast,
                    differentiateWithoutColor: differentiateWithoutColor,
                    onPlaceSelected: placeSelected,
                    onDropPiece: placeDraggedPiece
                )

                Text("Drag a piece onto the cove, choose an outlined position with a pointer or keyboard, or use Place selected piece. Every accepted position keeps the cove solvable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Harbor Tiles board")
            .accessibilityValue(
                "Cove \(game.currentCoveNumber) of 3. "
                    + "\(game.placedPieceIDs.count) of 3 pieces placed."
            )
            .accessibilityIdentifier("harborTiles.gameBoard")
        }
    }

    private var placeSelectedButton: some View {
        Button {
            guard let hint = game.hint() else { return }
            if game.selectedPieceID != hint.pieceID {
                _ = game.select(hint.pieceID)
            }
            placeSelected(at: hint.anchor)
        } label: {
            Label("Place selected piece", systemImage: "square.and.arrow.down.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .paceBackControlTarget()
        .keyboardShortcut(.return, modifiers: [])
        .disabled(game.hint() == nil)
        .accessibilityHint("Uses the first completion-preserving fit. There is no score or penalty.")
        .accessibilityIdentifier("harborTiles.placeSelected")
    }

    private var utilityControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { utilityButtons }
            VStack(spacing: 10) { utilityButtons }
        }
    }

    @ViewBuilder
    private var utilityButtons: some View {
        Button {
            showHint()
        } label: {
            Label("Show a fit", systemImage: "lightbulb.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .paceBackControlTarget()
        .disabled(game.hint() == nil)
        .accessibilityHint("Highlights one available position without a penalty")
        .accessibilityIdentifier("harborTiles.hint")

        Button {
            undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .paceBackControlTarget()
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!canUndo)
        .accessibilityHint("Returns the last piece with no penalty")
        .accessibilityIdentifier("harborTiles.undo")
    }

    private var coveCompleteCard: some View {
        PaceBackCard(style: .prominent, padding: 26) {
            VStack(alignment: .leading, spacing: 16) {
                beaconStrip
                Label("Cove \(game.currentCoveNumber) is lit", systemImage: "light.beacon.max.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityAddTraits(.isHeader)
                Text("Those three pieces fit. Nothing was scored, and there is no speed bonus.")
                    .foregroundStyle(.secondary)

                Button {
                    applyAdvance()
                } label: {
                    Label(
                        "Open cove \(game.currentCoveNumber + 1)",
                        systemImage: "arrow.right.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .paceBackControlTarget()
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityIdentifier("harborTiles.nextCove")

                Button {
                    undo()
                } label: {
                    Label("Undo last piece", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .paceBackControlTarget()
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityHint("Returns the last piece with no penalty")
            }
        }
    }

    private var completionCard: some View {
        PaceBackCard(style: .prominent, padding: 26) {
            VStack(alignment: .leading, spacing: 16) {
                beaconStrip
                Label("Three harbor lights are on", systemImage: "light.beacon.max.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityAddTraits(.isHeader)
                Text("Nine pieces placed. Nothing was scored. You can leave without replaying or reporting anything.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onEnd(game.summary)
                } label: {
                    Label("Continue", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .paceBackControlTarget()
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityHint("Returns to PaceBack. The game stores no session history.")
                .accessibilityIdentifier("harborTiles.finish")
            }
        }
    }

    private var beaconStrip: some View {
        HStack(spacing: 7) {
            ForEach(0..<HarborTilesGame.coveCount, id: \.self) { index in
                Image(systemName: index < game.completedCoveCount ? "light.beacon.max.fill" : "circle")
                    .foregroundStyle(index < game.completedCoveCount ? PaceBackDesign.accent : .secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.completedCoveCount) of 3 coves complete")
    }

    private var persistentExitControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { exitButtons }
            VStack(spacing: 10) { exitButtons }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var exitButtons: some View {
        Button {
            let transition = game.skip()
            if case .ended = transition { onEnd(game.summary) }
        } label: {
            Label("Skip", systemImage: "forward.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .paceBackControlTarget()
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .accessibilityLabel("Skip Harbor Tiles")
        .accessibilityHint("Leaves now. Skipping counts as complete.")
        .accessibilityIdentifier("harborTiles.skip")

        Button {
            let transition = game.stop()
            if case .ended = transition { onEnd(game.summary) }
        } label: {
            Label("Stop · enough for now", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(PaceBackDesign.warm)
        .paceBackControlTarget()
        .keyboardShortcut(".", modifiers: .command)
        .accessibilityHint("Stops now. Stopping counts as complete.")
        .accessibilityIdentifier("harborTiles.stop")
    }

    private var canUndo: Bool {
        game.placementHistory.last?.coveIndex == game.currentCoveIndex
    }

    private func select(_ pieceID: HarborTilesPieceID) {
        guard game.select(pieceID) == .selected(pieceID) else { return }
        hintedAnchor = nil
        lastMessage = HarborTilesCopy.selectionInstruction(
            pieceTitle: pieceID.title,
            for: game.ageBand
        )
    }

    private func placeSelected(at anchor: HarborTilesCell) {
        let beforePiece = game.selectedPieceID
        let beforeCove = game.currentCoveNumber
        let transition: HarborTilesTransition

        if reduceMotion {
            transition = game.place(at: anchor)
        } else {
            var animatedTransition: HarborTilesTransition = .rejected(.destinationUnavailable)
            withAnimation(.easeOut(duration: 0.16)) {
                animatedTransition = game.place(at: anchor)
            }
            transition = animatedTransition
        }

        hintedAnchor = nil
        switch transition {
        case .placed:
            lastMessage = "\(beforePiece?.title ?? "Piece") placed. Cove \(beforeCove), \(game.placedPieceIDs.count) of 3 pieces."
        case .coveCompleted:
            lastMessage = "Cove \(beforeCove) complete. Nothing was scored."
        case .ended(.completed):
            lastMessage = HarborTilesCopy.completion
        case .rejected:
            lastMessage = "That position is unavailable. The board did not change."
        default:
            break
        }
    }

    private func placeDraggedPiece(
        _ pieceID: HarborTilesPieceID,
        at anchor: HarborTilesCell
    ) -> Bool {
        let beforeCove = game.currentCoveNumber
        let transition: HarborTilesTransition

        if reduceMotion {
            transition = game.place(pieceID: pieceID, at: anchor)
        } else {
            var animatedTransition: HarborTilesTransition = .rejected(.destinationUnavailable)
            withAnimation(.easeOut(duration: 0.16)) {
                animatedTransition = game.place(pieceID: pieceID, at: anchor)
            }
            transition = animatedTransition
        }

        hintedAnchor = nil
        switch transition {
        case .placed:
            lastMessage = "\(pieceID.title) placed. Cove \(beforeCove), \(game.placedPieceIDs.count) of 3 pieces."
        case .coveCompleted:
            lastMessage = "Cove \(beforeCove) complete. Nothing was scored."
        case .ended(.completed):
            lastMessage = HarborTilesCopy.completion
        case .rejected:
            // Atomic placement leaves both selection and board state untouched
            // when a direct-manipulation destination is invalid.
            lastMessage = "That drop is unavailable. The board did not change."
            return false
        default:
            break
        }
        return true
    }

    private func showHint() {
        guard let hint = game.hint() else { return }
        _ = game.select(hint.pieceID)
        hintedAnchor = hint.anchor
        lastMessage = "A fit is outlined for \(hint.pieceID.title), row \(hint.anchor.row + 1), column \(hint.anchor.column + 1)."
    }

    private func undo() {
        guard case .undone(let pieceID) = game.undo() else { return }
        hintedAnchor = nil
        lastMessage = "\(pieceID.title) returned to the tray. There is no penalty."
    }

    private func applyAdvance() {
        guard case .advanced(let coveNumber) = game.advanceCove() else { return }
        hintedAnchor = nil
        lastMessage = "Cove \(coveNumber) is ready. Choose any available piece."
    }
}

private struct HarborTilesBoard: View {
    let game: HarborTilesGame
    let hintedAnchor: HarborTilesCell?
    let contrast: ColorSchemeContrast
    let differentiateWithoutColor: Bool
    let onPlaceSelected: (HarborTilesCell) -> Void
    let onDropPiece: (HarborTilesPieceID, HarborTilesCell) -> Bool

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 50), spacing: 8),
        count: HarborTilesGame.boardSize
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<HarborTilesGame.boardSize, id: \.self) { row in
                ForEach(0..<HarborTilesGame.boardSize, id: \.self) { column in
                    boardCell(HarborTilesCell(row: row, column: column))
                }
            }
        }
        .frame(maxWidth: 390)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func boardCell(_ cell: HarborTilesCell) -> some View {
        let isTarget = game.currentCove?.targetCells.contains(cell) == true
        let isOccupied = game.occupiedCells.contains(cell)
        let isValidAnchor = game.selectedPieceID.map {
            game.validAnchors(for: $0).contains(cell)
        } ?? false
        let isHinted = hintedAnchor == cell

        if !isTarget {
            RoundedRectangle(cornerRadius: 10)
                .fill(PaceBackDesign.calmBlue.opacity(0.035))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "water.waves")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.35))
                }
                .accessibilityHidden(true)
                .dropDestination(for: String.self) { items, _ in
                    return handleDrop(items, at: cell)
                }
        } else if isOccupied {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [PaceBackDesign.calmBlue, PaceBackDesign.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: differentiateWithoutColor ? "diamond.fill" : "sparkle")
                        .foregroundStyle(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(contrast == .increased ? 0.95 : 0.62), lineWidth: 2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Row \(cell.row + 1), column \(cell.column + 1), filled sea-glass tile")
                .dropDestination(for: String.self) { items, _ in
                    return handleDrop(items, at: cell)
                }
        } else {
            ZStack {
                Button {
                    onPlaceSelected(cell)
                } label: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            isHinted
                                ? PaceBackDesign.warm.opacity(0.22)
                                : PaceBackDesign.calmBlue.opacity(isValidAnchor ? 0.14 : 0.055)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isHinted
                                        ? PaceBackDesign.warm
                                        : PaceBackDesign.calmBlue.opacity(isValidAnchor ? 0.82 : 0.30),
                                    style: StrokeStyle(
                                        lineWidth: isHinted || contrast == .increased ? 2.5 : 1.5,
                                        dash: isValidAnchor ? [5, 4] : []
                                    )
                                )
                        }
                        .overlay {
                            if isValidAnchor {
                                Image(systemName: isHinted ? "lightbulb.fill" : "plus")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(isHinted ? PaceBackDesign.warm : PaceBackDesign.calmBlue)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isValidAnchor)
                .accessibilityLabel("Row \(cell.row + 1), column \(cell.column + 1)")
                .accessibilityValue(isValidAnchor ? "Available fit" : "Unavailable for selected piece")
                .accessibilityHint(
                    isValidAnchor
                        ? "Places the selected piece here"
                        : "Choose another outlined position or drag a compatible piece"
                )
                .accessibilityIdentifier("harborTiles.cell.r\(cell.row).c\(cell.column)")
            }
            .aspectRatio(1, contentMode: .fit)
            .dropDestination(for: String.self) { items, _ in
                return handleDrop(items, at: cell)
            }
        }
    }

    private func handleDrop(_ items: [String], at cell: HarborTilesCell) -> Bool {
        guard items.count == 1,
              let rawPieceID = items.first,
              let pieceID = HarborTilesPieceID(rawValue: rawPieceID) else {
            return false
        }
        return onDropPiece(pieceID, cell)
    }
}

private struct HarborTilesPiecePreview: View {
    let pieceID: HarborTilesPieceID
    let cellSize: CGFloat

    var body: some View {
        let maximumRow = pieceID.offsets.map(\.row).max() ?? 0
        let maximumColumn = pieceID.offsets.map(\.column).max() ?? 0

        VStack(spacing: 3) {
            ForEach(0...maximumRow, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0...maximumColumn, id: \.self) { column in
                        let occupied = pieceID.offsets.contains(
                            HarborTilesCell(row: row, column: column)
                        )
                        RoundedRectangle(cornerRadius: 3)
                            .fill(occupied ? PaceBackDesign.calmBlue : .clear)
                            .frame(width: cellSize, height: cellSize)
                            .overlay {
                                if occupied {
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(PaceBackDesign.accent.opacity(0.7), lineWidth: 1)
                                }
                            }
                    }
                }
            }
        }
    }
}

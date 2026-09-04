import SwiftUI

/// A finite, low-stimulation waypoint game with native macOS buttons and
/// keyboard equivalents. The parent receives only a closed summary when the
/// user completes, skips, or stops.
public struct HarborPathGameView: View {
    @State private var game: HarborPathGame
    @State private var lastPlacedItemTitle: String?

    private let onEnd: (HarborPathGameSummary) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        game: HarborPathGame,
        onEnd: @escaping (HarborPathGameSummary) -> Void
    ) {
        _game = State(initialValue: game)
        self.onEnd = onEnd
    }

    public var body: some View {
        ZStack {
            PaceBackCanvasBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        gameHeader

                        if game.isActive {
                            activeBoard
                        } else {
                            completedBoard
                        }

                        Text(HarborPathCopy.careBoundary)
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
                    persistentGameControls
                }
            }
        }
        .frame(minWidth: 660, minHeight: 650)
        .navigationTitle("Harbor Path")
    }

    private var gameHeader: some View {
        PaceBackCard(style: .quiet) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                    .font(.title)
                    .foregroundStyle(PaceBackDesign.accent)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("OPTIONAL GENTLE GAME")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(PaceBackDesign.accent)
                    Text("Harbor Path")
                        .font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(HarborPathCopy.promise)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("No score · no timer · no losing · no forced breathing")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
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

    private var activeBoard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let lastPlacedItemTitle {
                Label("\(lastPlacedItemTitle) placed. The next optional waypoint is ready.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityIdentifier("harborPath.turnAcknowledgement")
            }

            if let checkpointID = game.currentCheckpointID,
               let checkpointNumber = game.currentCheckpointNumber {
                checkpointCard(checkpointID, number: checkpointNumber)
                    .id(checkpointID)
                    .transition(reduceMotion ? .identity : .opacity)
            }

            boardCard
        }
    }

    private func checkpointCard(
        _ checkpointID: QuietHarborPromptID,
        number: Int
    ) -> some View {
        let copy = checkpointID.harborPathCopy(for: game.presentation)

        return PaceBackCard(style: .prominent, padding: 26) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    checkpointToken(checkpointID)
                    checkpointCopy(copy, number: number)
                }
                VStack(alignment: .leading, spacing: 16) {
                    checkpointToken(checkpointID)
                    checkpointCopy(copy, number: number)
                }
            }
        }
    }

    private func checkpointToken(_ checkpointID: QuietHarborPromptID) -> some View {
        ZStack {
            Circle()
                .fill(PaceBackDesign.calmBlue.opacity(0.12))
            Circle()
                .strokeBorder(PaceBackDesign.calmBlue.opacity(0.48), lineWidth: 1.5)
            Image(systemName: checkpointID.harborPathItemID.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(PaceBackDesign.calmBlue)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private func checkpointCopy(
        _ copy: HarborPathCheckpointCopy,
        number: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WAYPOINT \(number) OF \(game.checkpointIDs.count)")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PaceBackDesign.accent)
            Text(copy.title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(copy.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose the action below, skip this clue, or stop. Every choice is allowed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Waypoint \(number) of \(game.checkpointIDs.count). \(copy.title). \(copy.detail)"
        )
        .accessibilityIdentifier("harborPath.checkpoint.\(game.currentCheckpointID?.rawValue ?? "none")")
    }

    private var boardCard: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Lantern route", systemImage: "map.fill")
                        .font(.headline)
                    Spacer()
                    if let number = game.currentCheckpointNumber {
                        Text("WAYPOINT \(number) OF \(game.checkpointIDs.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                HarborPathScene(game: game)

                Text(HarborPathCopy.noCompetition)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var completedBoard: some View {
        PaceBackCard(style: .prominent, padding: 26) {
            VStack(alignment: .leading, spacing: 18) {
                Label(completionEyebrow, systemImage: completionSymbol)
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(PaceBackDesign.accent)
                HarborPathScene(game: game)
                Text(completionTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(completionDetail)
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
                .accessibilityHint("Returns to Softer. The game stores no session history.")
                .accessibilityIdentifier("harborPath.finish")
            }
        }
    }

    private var persistentGameControls: some View {
        VStack(spacing: 10) {
            primaryPlacementControl

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { exitControls }
                VStack(spacing: 10) { exitControls }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var primaryPlacementControl: some View {
        if let checkpointID = game.currentCheckpointID {
            let copy = checkpointID.harborPathCopy(for: game.presentation)
            Button {
                apply(.placeHarborItem)
            } label: {
                Label(copy.actionTitle, systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .paceBackControlTarget()
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("Places one static item and moves to the next optional waypoint")
            .accessibilityIdentifier("harborPath.placeHarborItem")
        }
    }

    @ViewBuilder
    private var exitControls: some View {
        Button {
            apply(.skipCheckpoint)
        } label: {
            Label("Skip this waypoint", systemImage: "forward.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .paceBackControlTarget()
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .accessibilityLabel("Skip this waypoint")
        .accessibilityHint("Moves to the next optional waypoint without placing an item")
        .accessibilityIdentifier("harborPath.skip")

        Button {
            apply(.stop)
        } label: {
            Label("Stop · enough for now", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(PaceBackDesign.warm)
        .paceBackControlTarget()
        .keyboardShortcut(".", modifiers: .command)
        .accessibilityHint("Stops the game. Stopping counts as complete.")
        .accessibilityIdentifier("harborPath.stop")
    }

    private func apply(_ actionID: HarborPathActionID) {
        let checkpointID = game.currentCheckpointID
        let transition: HarborPathTransition

        if reduceMotion {
            transition = game.send(actionID)
        } else {
            var animatedTransition: HarborPathTransition = .ignored
            withAnimation(.easeOut(duration: 0.16)) {
                animatedTransition = game.send(actionID)
            }
            transition = animatedTransition
        }

        if actionID == .placeHarborItem, let checkpointID {
            lastPlacedItemTitle = checkpointID.harborPathItemID.accessibilityTitle
        }

        switch transition {
        case .ended(.skippedComplete), .ended(.stoppedComplete):
            onEnd(game.summary)
        case .ended(.pathComplete), .ended(.active), .advanced, .ignored:
            break
        }
    }

    private var completionSymbol: String {
        switch game.resolutionID {
        case .pathComplete: "house.fill"
        case .skippedComplete: "forward.fill"
        case .stoppedComplete: "hand.raised.fill"
        case .active: "location.fill"
        }
    }

    private var completionEyebrow: String {
        switch game.resolutionID {
        case .pathComplete: "PATH COMPLETE"
        case .skippedComplete: "SKIPPED"
        case .stoppedComplete: "STOPPED"
        case .active: "HARBOR PATH"
        }
    }

    private var completionTitle: String {
        switch game.resolutionID {
        case .pathComplete: "The lantern reached home"
        case .skippedComplete: "Leaving counts as complete"
        case .stoppedComplete: "Enough for now"
        case .active: "Choose what feels manageable"
        }
    }

    private var completionDetail: String {
        switch game.resolutionID {
        case .pathComplete: HarborPathCopy.completed
        case .skippedComplete: HarborPathCopy.skipped
        case .stoppedComplete: HarborPathCopy.stopped
        case .active: HarborPathCopy.promise
        }
    }
}

private struct HarborPathScene: View {
    let game: HarborPathGame

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            routeEndpoint(symbol: "sailboat.fill", label: "Start")

            ForEach(Array(game.checkpointIDs.enumerated()), id: \.element.rawValue) { index, checkpointID in
                routeSegment(isComplete: index < game.checkpointResults.count)
                checkpointNode(checkpointID, index: index)
            }

            routeSegment(isComplete: game.resolutionID == .pathComplete)
            routeEndpoint(symbol: "house.fill", label: "Harbor home")
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(
            LinearGradient(
                colors: [
                    PaceBackDesign.calmBlue.opacity(0.12),
                    PaceBackDesign.accent.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(PaceBackDesign.calmBlue.opacity(contrast == .increased ? 0.55 : 0.20))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Harbor Path game board")
        .accessibilityValue(sceneAccessibilityValue)
        .accessibilityIdentifier("harborPath.gameBoard")
    }

    private func routeEndpoint(symbol: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(PaceBackDesign.accent)
                .frame(width: 44, height: 44)
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func routeSegment(isComplete: Bool) -> some View {
        Capsule()
            .fill(
                isComplete
                    ? PaceBackDesign.accent
                    : Color.primary.opacity(contrast == .increased ? 0.45 : 0.24)
            )
            .frame(maxWidth: .infinity, minHeight: 3, maxHeight: 3)
            .accessibilityHidden(true)
    }

    private func checkpointNode(_ checkpointID: QuietHarborPromptID, index: Int) -> some View {
        let result = game.checkpointResults.first { $0.checkpointID == checkpointID }
        let isCurrent = game.currentCheckpointID == checkpointID
        let isPlaced = result?.resultID == .waypointPlaced

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        isPlaced
                            ? PaceBackDesign.accent
                            : PaceBackDesign.calmBlue.opacity(isCurrent ? 0.20 : 0.08)
                    )
                Circle()
                    .strokeBorder(
                        isCurrent ? PaceBackDesign.warm : PaceBackDesign.calmBlue.opacity(0.45),
                        lineWidth: isCurrent || contrast == .increased ? 2.5 : 1.5
                    )
                Image(systemName: checkpointID.harborPathItemID.symbol)
                    .foregroundStyle(isPlaced ? .white : PaceBackDesign.calmBlue)
            }
            .frame(width: 48, height: 48)

            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Waypoint \(index + 1), \(checkpointID.harborPathItemID.accessibilityTitle)"
        )
        .accessibilityValue(isPlaced ? "Placed" : (isCurrent ? "Current" : "Not reached"))
    }

    private var sceneAccessibilityValue: String {
        if game.resolutionID == .pathComplete {
            return "Path complete. \(game.placedItemIDs.count) static items placed. Nothing was scored."
        }
        return "\(game.placedItemIDs.count) of \(game.checkpointIDs.count) static items placed."
    }
}

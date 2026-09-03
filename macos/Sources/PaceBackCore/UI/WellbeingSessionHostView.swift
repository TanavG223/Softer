import SwiftUI

struct WellbeingSessionHostView: View {
    private enum Phase: Equatable {
        case introduction
        case activity
        case checkout
        case finished(WellbeingOutcome, saved: Bool)
    }

    @Environment(\.dismiss) private var dismiss

    let store: AppStore
    let profile: LocalProfile
    let launch: WellbeingLaunch

    @State private var phase: Phase = .introduction
    @State private var stepIndex = 0
    @State private var isSaving = false
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        Group {
            if phase == .activity, launch.activityID.isGame {
                gameContent
            } else {
                standardSessionContent
            }
        }
        .navigationTitle(launch.activityID.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Stop") { stopAndLeave() }
                    .keyboardShortcut(".", modifiers: .command)
                    .accessibilityHint("Stops this activity without recording a check-out")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.presentedSheet = .support
                } label: {
                    Label("Need help now?", systemImage: "heart.text.square.fill")
                }
                .accessibilityHint("Opens static human-support options; no profile or activity result is used")
            }
        }
        .onAppear { headingFocused = true }
        .onDisappear {
            if store.activeWellbeingSession?.activityID == launch.activityID {
                store.cancelWellbeingActivity()
            }
        }
    }

    private var standardSessionContent: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sessionHeader
                    CaregiverUseNotice(ageBand: profile.ageBand)
                    phaseContent
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var sessionHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: launch.activityID.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PaceBackDesign.accent)
                .frame(width: 56, height: 56)
                .background(PaceBackDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("OPTIONAL ACTIVITY · \(launch.activityID.durationLabel.uppercased())")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(PaceBackDesign.accent)
                Text(launch.activityID.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                Text(launch.activityID.shortDetail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .introduction:
            introductionCard
        case .activity:
            if launch.activityID == .gentleBreathing {
                breathingPacerContent
            } else if launch.activityID == .screenOffPause {
                screenOffContent
            } else if launch.activityID == .trustedConnection {
                trustedConnectionContent
            } else {
                instructionContent
            }
        case .checkout:
            checkoutCard
        case .finished(let outcome, let saved):
            finishedCard(outcome: outcome, saved: saved)
        }
    }

    private var introductionCard: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 17) {
                Text("Before you begin")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(safetyCopy)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if store.startWellbeingActivity(
                        launch.activityID,
                        for: launch.needID,
                        at: .now
                    ) {
                        phase = .activity
                        headingFocused = true
                    }
                } label: {
                    Label(
                        launch.activityID.isGame ? "Open \(launch.activityID.title)" : "Begin",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Not now") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var breathingPacerContent: some View {
        BreathingPacerView(
            reduceMotionOverride: store.preferences.reduceMotionOverride,
            onFinish: { phase = .checkout },
            onSkip: { save(.skipped) },
            onStop: { stopAndLeave() }
        )
    }

    private var instructionContent: some View {
        let instructions = launch.activityID.instructions
        let safeIndex = min(stepIndex, max(0, instructions.count - 1))

        return PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("STEP \(safeIndex + 1) OF \(instructions.count)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(PaceBackDesign.accent)
                Text(instructions[safeIndex])
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Button(safeIndex == instructions.count - 1 ? "That is enough" : "Next") {
                    if safeIndex == instructions.count - 1 {
                        phase = .checkout
                    } else {
                        stepIndex += 1
                        headingFocused = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)

                sessionExitActions
            }
        }
    }

    private var screenOffContent: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 17) {
                Label("No countdown. No required return.", systemImage: "display.slash")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                Text(
                    profile.ageBand.isUnder13
                        ? "If it fits, a caregiver can step away from the Mac and offer a quieter moment together. PaceBack will not alert you or require a check-in."
                        : "If it feels possible, step away from the Mac. PaceBack will not start a timer, play a sound, or require you to come back."
                )
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

                Button("Step away without a check-out") {
                    store.cancelWellbeingActivity()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("Stay here and check out") { phase = .checkout }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var trustedConnectionContent: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 17) {
                Text(profile.ageBand.isUnder13 ? "Choose a familiar adult together" : "You choose who to contact")
                    .font(.title2.weight(.semibold))
                Text(
                    profile.ageBand.isUnder13
                        ? "A caregiver reviews the message and chooses the recipient. PaceBack never selects a person or sends anything automatically."
                        : "PaceBack can open the system share menu with a neutral draft. You review it, choose a recipient, and decide whether to send."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                ShareLink(item: connectionMessage) {
                    Label("Choose how to reach someone", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Continue to optional check-out") { phase = .checkout }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Skip") { save(.skipped) }
                    .buttonStyle(.plain)
                    .frame(minHeight: PaceBackDesign.minimumControlHeight)
            }
        }
    }

    @ViewBuilder
    private var gameContent: some View {
        switch launch.activityID {
        case .harborTiles:
            switch HarborTilesGame.prepare(
                ageBand: profile.ageBand,
                variantIndex: Int.random(in: 0..<6)
            ) {
            case .ready(let game):
                HarborTilesGameView(game: game) { summary in
                    switch summary.resolutionID {
                    case .completed:
                        phase = .checkout
                        headingFocused = true
                    case .skipped, .stopped, .active:
                        stopAndLeave()
                    }
                }
            case .unavailable:
                unavailableGame
            }
        case .harborPath:
            switch HarborPathGame.prepare(ageBand: profile.ageBand, checkpointCount: 3) {
            case .ready(let game):
                HarborPathGameView(game: game) { summary in
                    switch summary.resolutionID {
                    case .pathComplete:
                        phase = .checkout
                        headingFocused = true
                    case .skippedComplete, .stoppedComplete, .active:
                        stopAndLeave()
                    }
                }
            case .unavailable:
                unavailableGame
            }
        default:
            EmptyView()
        }
    }

    private var unavailableGame: some View {
        PaceBackCard(style: .quiet) {
            ContentUnavailableView(
                "This game is not available",
                systemImage: "display.slash",
                description: Text("Return to Toolkit for an age- and role-available option.")
            )
        }
    }

    private var checkoutCard: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 15) {
                Text(profile.ageBand.isUnder13 ? "What did you notice?" : "How was that for you?")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(
                    profile.ageBand.isUnder13
                        ? "This optional caregiver observation is about this activity only—not a diagnosis, child report, or mental-health score."
                        : "This optional answer is about this activity in this moment—not a diagnosis, safety check, or mental-health score."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(WellbeingOutcome.allCases) { outcome in
                    Button {
                        save(outcome)
                    } label: {
                        HStack {
                            Text(outcome.title)
                            Spacer()
                            if isSaving {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(outcome == .lessSettled ? PaceBackDesign.warm : PaceBackDesign.accent)
                    .disabled(isSaving)
                }
            }
        }
    }

    private func finishedCard(outcome: WellbeingOutcome, saved: Bool) -> some View {
        PaceBackCard(style: outcome == .lessSettled ? .caution : .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Label(
                    outcome == .lessSettled ? "Stopping was the right move" : "That is enough for now",
                    systemImage: outcome == .lessSettled ? "hand.raised.fill" : "checkmark.circle.fill"
                )
                .font(.title2.weight(.semibold))
                .foregroundStyle(outcome == .lessSettled ? PaceBackDesign.warm : PaceBackDesign.accent)

                Text(finishedCopy(outcome: outcome, saved: saved))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if outcome == .lessSettled {
                    if let alternative = lessSettledAlternative {
                        NavigationLink(
                            value: WellbeingLaunch(needID: launch.needID, activityID: alternative)
                        ) {
                            Label("Try a different option: \(alternative.title)", systemImage: alternative.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button {
                        store.presentedSheet = .support
                    } label: {
                        Label("Contact a person or get urgent help", systemImage: "heart.text.square.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button("Return to Calm") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var sessionExitActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { exitButtons }
            VStack(spacing: 12) { exitButtons }
        }
    }

    @ViewBuilder
    private var exitButtons: some View {
        Button("Skip") { save(.skipped) }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        Button("Stop · enough for now") { stopAndLeave() }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
    }

    private var lessSettledAlternative: WellbeingActivityID? {
        guard let recommendation = store.wellbeingRecommendation,
              recommendation.canStart,
              recommendation.activityID != launch.activityID else {
            return nil
        }
        return recommendation.activityID
    }

    private var safetyCopy: String {
        switch launch.activityID {
        case .gentleBreathing:
            "Let your breath stay comfortable and unforced. Do not hold it or force a deep breath. Stop for dizziness, light-headedness, shortness of breath, or feeling worse."
        case .muscleRelease:
            "Never strain. Skip painful, injured, spasm-prone, or recently operated areas. Release-only is enough."
        case .comfortableMovement:
            "Stay within your usual comfortable range. Stop for pain, dizziness, chest pain, unusual breathlessness, or feeling worse."
        case .orientOutside, .harborPath, .harborTiles:
            "Keep your eyes open if you prefer. Skip any prompt and stop if distress, frustration, unreality, or feeling unsafe increases."
        case .trustedConnection:
            "You or the caregiver choose the person and what to share. PaceBack never selects a recipient or sends anything automatically."
        case .screenOffPause:
            "This is a low-stimulation pause, not a task to complete. Leave immediately if that is the better choice."
        case .oneSmallStep:
            "Choose only something safe and manageable. Doing nothing right now is also valid."
        }
    }

    private var connectionMessage: String {
        profile.ageBand.isUnder13
            ? "Could you check in with us when you have a moment? No need to solve anything."
            : "Could you check in with me when you have a moment? I could use some company. No need to solve anything."
    }

    private func save(_ outcome: WellbeingOutcome) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let saved = await store.checkoutWellbeingActivity(outcome, at: .now)
            isSaving = false
            phase = .finished(outcome, saved: saved)
            headingFocused = true
        }
    }

    private func stopAndLeave() {
        store.cancelWellbeingActivity()
        dismiss()
    }

    private func finishedCopy(outcome: WellbeingOutcome, saved: Bool) -> String {
        let persistence: String
        if store.isGuestSession {
            persistence = "Nothing was saved. This check-out may adjust suggestions only until you leave the temporary guest session."
        } else if saved {
            persistence = "Your closed check-out was saved locally and may only change the ordering of available activities."
        } else {
            persistence = "The check-out could not be saved; no result was inferred from the activity."
        }
        switch outcome {
        case .moreSettled:
            return "That describes only this moment; it is not proof of improvement. \(persistence)"
        case .same:
            return "Different options fit different people and moments. \(persistence)"
        case .lessSettled:
            return "Do not push through. This exact activity will be left out of automatic suggestions for 24 hours; that is not a diagnosis or risk assessment. \(persistence)"
        case .skipped:
            return "Skipping counts as a complete choice here. \(persistence)"
        }
    }
}

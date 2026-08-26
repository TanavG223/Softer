import SwiftUI

struct FocusSessionView: View {
    let store: AppStore
    let profile: LocalProfile

    @State private var focusMinutes = 15
    @State private var restMinutes = 5
    @State private var machine = FocusSessionMachine(configuration: .init())
    @State private var startingSymptomRating = 0
    @State private var symptomRating = 0
    @State private var note = ""
    @State private var didRecord = false
    @State private var pausedForHigherRating = false

    var body: some View {
        ContentScaffold(
            "Focus Session",
            subtitle: "A user-set timer for a confirmed plan—not a treatment recommendation or clearance decision.",
            eyebrow: "GUIDED PACING · USER CONTROLLED",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            SafetyBoundaryNotice()
            sessionPanel
            checkInPanel
        }
        .task(id: machine.phase) {
            guard machine.isRunning else { return }
            while !Task.isCancelled && machine.isRunning {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                machine.tick()
            }
        }
    }

    private var sessionPanel: some View {
        PaceBackCard(style: .prominent, padding: 26) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionHeading)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(sessionDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(phaseTitle, kind: phaseBadgeKind)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 36) {
                        SessionDial(
                            progress: progress,
                            timeText: timeText,
                            phaseTitle: phaseTitle,
                            accessibilityLabel: timeAccessibilityLabel
                        )
                        sessionControls
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        SessionDial(
                            progress: progress,
                            timeText: timeText,
                            phaseTitle: phaseTitle,
                            accessibilityLabel: timeAccessibilityLabel
                        )
                        .frame(maxWidth: .infinity)
                        sessionControls
                    }
                }

                if pausedForHigherRating {
                    PaceBackNotice(
                        "The entered rating is higher than at the start, so the timer paused. PaceBack does not interpret the change. Review the confirmed plan or contact the care team before deciding whether to resume.",
                        title: "Timer paused after check-in",
                        style: .caution
                    )
                    .accessibilityLabel(
                        "Timer paused after a higher symptom rating. Review the confirmed care plan or contact the care team before deciding whether to resume."
                    )
                }
            }
        }
    }

    private var sessionControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if machine.phase == .ready {
                readyConfiguration
            } else {
                PaceBackNotice(
                    "The timer follows the times you entered. It does not change the care plan or decide when to progress.",
                    style: .local
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { sessionButtons }
                VStack(alignment: .leading, spacing: 8) { sessionButtons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readyConfiguration: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("SET FROM THE CONFIRMED PLAN")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    durationStepper(title: "Focus", value: $focusMinutes, range: 1...60)
                    durationStepper(title: "Planned rest", value: $restMinutes, range: 1...30)
                }
                VStack(alignment: .leading, spacing: 10) {
                    durationStepper(title: "Focus", value: $focusMinutes, range: 1...60)
                    durationStepper(title: "Planned rest", value: $restMinutes, range: 1...30)
                }
            }

            Divider()
            ratingControl(
                title: "Starting symptom rating",
                value: Binding(
                    get: { startingSymptomRating },
                    set: {
                        startingSymptomRating = $0
                        symptomRating = $0
                    }
                ),
                hint: "This value is recorded descriptively and is not interpreted as readiness"
            )
        }
    }

    private func durationStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text("\(value.wrappedValue) minutes")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .paceBackControlTarget()
        .accessibilityValue("\(value.wrappedValue) minutes")
    }

    @ViewBuilder
    private var sessionButtons: some View {
        primaryButton

        if machine.phase == .focusing || machine.phase == .resting || machine.phase == .paused {
            Button("Stop early", role: .destructive) { machine.stopEarly() }
                .buttonStyle(.bordered)
                .paceBackControlTarget()
                .accessibilityHint("Stops this timer without making a clearance decision")
        }

        if [.completed, .stoppedEarly].contains(machine.phase) {
            Button {
                reset()
            } label: {
                Label("Start a new session", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .paceBackControlTarget()
        }
    }

    private var checkInPanel: some View {
        PaceBackCard(padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optional check-in")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Record what was entered. PaceBack does not label the result better or worse.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge("Descriptive only", kind: .informational)
                }

                ratingControl(
                    title: "Current symptom rating",
                    value: Binding(
                        get: { symptomRating },
                        set: { newRating in
                            symptomRating = newRating
                            if machine.applyCheckIn(
                                startingRating: startingSymptomRating,
                                currentRating: symptomRating
                            ) {
                                pausedForHigherRating = true
                            }
                        }
                    ),
                    hint: "If the entered rating is higher than the starting value during a session, the timer pauses"
                )

                TextField("Optional note", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .paceBackControlTarget()
                    .accessibilityHint("Notes stay in this encrypted profile")

                HStack(spacing: 12) {
                    Button {
                        didRecord = true
                        Task {
                            await store.recordTrend(
                                symptomRating: symptomRating,
                                focusMinutes: machine.elapsedFocusSeconds / 60,
                                note: note
                            )
                        }
                    } label: {
                        Label("Record this check-in", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .paceBackControlTarget()
                    .disabled(didRecord || machine.phase == .ready)

                    if didRecord {
                        Label("Saved to this profile", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(PaceBackDesign.accent)
                    }
                }
            }
        }
    }

    private func ratingControl(title: String, value: Binding<Int>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("\(value.wrappedValue) / 10")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...10,
                step: 1
            ) {
                Text(title)
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("10")
            }
            .accessibilityValue("\(value.wrappedValue) out of 10")
            .accessibilityHint(hint)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch machine.phase {
        case .ready:
            Button {
                symptomRating = startingSymptomRating
                pausedForHigherRating = false
                machine = FocusSessionMachine(
                    configuration: FocusSessionConfiguration(focusMinutes: focusMinutes, restMinutes: restMinutes)
                )
                machine.start()
            } label: {
                Label("Start focus timer", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .paceBackControlTarget()
            .keyboardShortcut(.space, modifiers: [])

        case .focusing, .resting:
            Button {
                machine.pause()
            } label: {
                Label("Pause timer", systemImage: "pause.fill")
            }
            .buttonStyle(.borderedProminent)
            .paceBackControlTarget()
            .keyboardShortcut(.space, modifiers: [])

        case .paused:
            Button {
                machine.resume()
            } label: {
                Label("Resume timer", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .paceBackControlTarget()
            .keyboardShortcut(.space, modifiers: [])

        case .completed, .stoppedEarly:
            EmptyView()
        }
    }

    private var sessionHeading: String {
        switch machine.phase {
        case .ready: "Set a plan-based pace"
        case .focusing: "Focus interval in progress"
        case .paused: "Timer paused"
        case .resting: "Planned rest interval"
        case .completed: "Timer complete"
        case .stoppedEarly: "Session stopped"
        }
    }

    private var sessionDetail: String {
        switch profile.actingRole {
        case .guardian, .caregiver: "Stay with the confirmed instructions and keep the person’s comfort in control."
        case .teenUser: "You can pause or stop at any time; a guardian controls changes to the care plan."
        case .selfManaged: "You control the timer and can pause or stop at any time."
        }
    }

    private var phaseTitle: String {
        switch machine.phase {
        case .ready: "Ready"
        case .focusing: "Focus"
        case .paused: "Paused"
        case .resting: "Planned rest"
        case .completed: "Completed"
        case .stoppedEarly: "Stopped early"
        }
    }

    private var phaseBadgeKind: StatusBadge.Kind {
        switch machine.phase {
        case .focusing, .completed: .safe
        case .paused, .stoppedEarly: .caution
        case .ready, .resting: .informational
        }
    }

    private var shownSeconds: Int {
        switch machine.phase {
        case .ready: focusMinutes * 60
        case .resting: machine.restSecondsRemaining
        default: machine.focusSecondsRemaining
        }
    }

    private var timeText: String {
        String(format: "%02d:%02d", shownSeconds / 60, shownSeconds % 60)
    }

    private var timeAccessibilityLabel: String {
        "\(phaseTitle). \(shownSeconds / 60) minutes and \(shownSeconds % 60) seconds remaining"
    }

    private var progress: Double {
        switch machine.phase {
        case .ready: 0
        case .focusing, .paused:
            Double(machine.elapsedFocusSeconds) / Double(machine.configuration.focusMinutes * 60)
        case .resting:
            Double(machine.elapsedRestSeconds) / Double(machine.configuration.restMinutes * 60)
        case .completed: 1
        case .stoppedEarly:
            Double(machine.elapsedFocusSeconds) / Double(machine.configuration.focusMinutes * 60)
        }
    }

    private func reset() {
        machine = FocusSessionMachine(
            configuration: FocusSessionConfiguration(focusMinutes: focusMinutes, restMinutes: restMinutes)
        )
        didRecord = false
        pausedForHigherRating = false
        symptomRating = startingSymptomRating
        note = ""
    }
}

private struct SessionDial: View {
    let progress: Double
    let timeText: String
    let phaseTitle: String
    let accessibilityLabel: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.13), lineWidth: 13)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    AngularGradient(
                        colors: [PaceBackDesign.warm, PaceBackDesign.accent, PaceBackDesign.calmBlue],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 5) {
                Text(timeText)
                    .font(.system(size: 43, weight: .semibold, design: .rounded).monospacedDigit())
                Text(phaseTitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 212, height: 212)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

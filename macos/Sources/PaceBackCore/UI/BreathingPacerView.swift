import SwiftUI

/// A session-only visual rhythm. It records no timing, pace, or breathing data.
struct BreathingPacerView: View {
    enum Pace: String, CaseIterable, Identifiable {
        case steady
        case slower
        case spacious

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steady: "Steady"
            case .slower: "Slower"
            case .spacious: "Spacious"
            }
        }

        var growDuration: TimeInterval {
            switch self {
            case .steady: 4
            case .slower: 4.5
            case .spacious: 5
            }
        }

        var softenDuration: TimeInterval {
            switch self {
            case .steady: 4
            case .slower: 5.5
            case .spacious: 7
            }
        }
    }

    let reduceMotionOverride: Bool
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var pace: Pace = .slower
    @State private var startedAt = Date.now
    @State private var isPaused = false
    @State private var manualCueIsGrowing = true
    @State private var usesShapeOnlyWords = false

    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    var body: some View {
        PaceBackCard(style: .prominent, padding: 26) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FOLLOW ONLY IF COMFORTABLE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(PaceBackDesign.accent)
                    Text("Watch the shape, or breathe naturally")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("There is no required count. Pause, ignore the cue, or stop at any time.")
                        .foregroundStyle(.secondary)
                }

                Picker("Visual pace", selection: $pace) {
                    ForEach(Pace.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: pace) { _, _ in startedAt = .now }

                Toggle("Just watch · use shape-only words", isOn: $usesShapeOnlyWords)
                    .toggleStyle(.switch)
                    .accessibilityHint("Removes breathing language while keeping the same optional visual rhythm")

                if reduceMotion {
                    staticCue
                } else {
                    animatedCue
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { sessionControls }
                    VStack(spacing: 10) { sessionControls }
                }
            }
        }
        .accessibilityIdentifier("breathingPacer")
    }

    private var animatedCue: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
            let state = cueState(at: context.date)
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PaceBackDesign.calmBlue.opacity(0.12))
                    Circle()
                        .strokeBorder(PaceBackDesign.accent.opacity(0.78), lineWidth: 3)
                    Circle()
                        .fill(PaceBackDesign.accent.opacity(0.20))
                        .padding(26)
                }
                .frame(width: 210, height: 210)
                .scaleEffect(0.68 + (0.32 * state.progress))
                .animation(.easeInOut(duration: 0.18), value: state.progress)
                .accessibilityHidden(true)

                Text(isPaused ? "Paused · rest however feels comfortable" : cueLabel(isGrowing: state.isGrowing))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                    .accessibilityLabel(isPaused ? "Visual cue paused" : cueLabel(isGrowing: state.isGrowing))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var staticCue: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(PaceBackDesign.calmBlue.opacity(0.14))
                Circle()
                    .strokeBorder(PaceBackDesign.accent, lineWidth: 3)
                Image(systemName: manualCueIsGrowing ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(PaceBackDesign.accent)
            }
            .frame(width: 170, height: 170)
            .accessibilityHidden(true)

            Text(cueLabel(isGrowing: manualCueIsGrowing))
                .font(.title3.weight(.semibold))

            Button("Show next cue") {
                manualCueIsGrowing.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Changes the static cue without animation or a timer")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sessionControls: some View {
        if !reduceMotion {
            Button(isPaused ? "Resume visual" : "Pause visual") {
                isPaused.toggle()
                if !isPaused { startedAt = .now }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }

        Button("That is enough") { onFinish() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        Button("Skip") { onSkip() }
            .buttonStyle(.bordered)
            .controlSize(.large)

        Button("Stop") { onStop() }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(PaceBackDesign.warm)
    }

    private func cueState(at date: Date) -> (progress: Double, isGrowing: Bool) {
        let cycle = pace.growDuration + pace.softenDuration
        let elapsed = max(0, date.timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: cycle)
        if elapsed < pace.growDuration {
            return (elapsed / pace.growDuration, true)
        }
        let softenProgress = (elapsed - pace.growDuration) / pace.softenDuration
        return (1 - softenProgress, false)
    }

    private func cueLabel(isGrowing: Bool) -> String {
        if usesShapeOnlyWords {
            return isGrowing ? "Shape expanding" : "Shape softening"
        }
        return isGrowing ? "Let the shape grow as you breathe in naturally" : "Let the shape soften as you breathe out naturally"
    }
}

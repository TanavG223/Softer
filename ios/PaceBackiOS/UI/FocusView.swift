import SwiftUI

struct FocusView: View {
    let store: AppStore

    @State private var selectedMinutes = 10
    @State private var symptomBefore = 3.0
    @State private var symptomAfter = 3.0
    @State private var startedAt: Date?
    @State private var completed = false

    private var profile: LocalProfile { store.selectedProfile! }
    private let durations = [5, 10, 15]

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        "Focus without guessing",
                        detail: "Choose a short interval yourself, check in, and stop at any time. PaceBack never advances a recovery stage."
                    )
                    ProfileStrip(profile: profile)
                    if let startedAt {
                        activeSession(startedAt: startedAt)
                    } else if completed {
                        afterCheckIn
                    } else {
                        setup
                    }
                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var setup: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1 · Check in before starting")
                        .font(.headline)
                    Text("Current symptom burden: \(Int(symptomBefore)) out of 10")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Current symptom burden \(Int(symptomBefore)) out of 10")
                    Slider(value: $symptomBefore, in: 0...10, step: 1)
                        .tint(PaceBackDesign.accent)
                        .accessibilityLabel("Current symptom burden")
                        .accessibilityValue("\(Int(symptomBefore)) out of 10")
                    Text("This number is a private check-in, not a diagnosis or readiness score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("2 · Choose your interval")
                        .font(.headline)
                    Picker("Session length", selection: $selectedMinutes) {
                        ForEach(durations, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Choose a duration that already fits your clinician plan")
                }

                Button {
                    startedAt = .now
                    completed = false
                } label: {
                    Label("Start \(selectedMinutes)-minute focus", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Label(
                    "Use only a duration already allowed by your clinician-guided plan. Stop if you feel worse.",
                    systemImage: "hand.raised.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func activeSession(startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = TimeInterval(selectedMinutes * 60)
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let remaining = max(0, total - elapsed)

            PaceBackCard(style: .prominent) {
                VStack(spacing: 20) {
                    StatusPill(
                        text: remaining == 0 ? "Interval complete" : "Session running",
                        kind: remaining == 0 ? .local : .informational
                    )
                    Text(timeString(remaining))
                        .font(.system(size: 62, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .accessibilityLabel("\(Int(remaining)) seconds remaining")
                    ProgressView(value: min(elapsed, total), total: total)
                        .tint(PaceBackDesign.accent)
                    Text(
                        remaining == 0
                            ? "The timer is complete. Check in before choosing anything else."
                            : "This timer does not decide whether activity is safe. You stay in control."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    Button {
                        self.startedAt = nil
                        completed = true
                        symptomAfter = symptomBefore
                    } label: {
                        Label(
                            remaining == 0 ? "Continue to check-in" : "Stop and check in",
                            systemImage: "stop.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(remaining == 0 ? PaceBackDesign.accent : PaceBackDesign.warm)
                }
            }
        }
    }

    private var afterCheckIn: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Private after-session check-in", systemImage: "checkmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(PaceBackDesign.accent)
                Text("How do symptoms feel now? \(Int(symptomAfter)) out of 10")
                    .font(.headline)
                Slider(value: $symptomAfter, in: 0...10, step: 1)
                    .tint(PaceBackDesign.accent)
                    .accessibilityLabel("Symptoms after the session")
                    .accessibilityValue("\(Int(symptomAfter)) out of 10")
                if symptomAfter > symptomBefore {
                    Label(
                        "Symptoms increased. Pause here and follow the plan you made with your clinician. If a danger sign is present, use the emergency check now.",
                        systemImage: "pause.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(PaceBackDesign.warm)
                } else {
                    Text("PaceBack records no recovery conclusion from this check-in and does not unlock a next stage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Finish check-in") {
                    completed = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    NavigationStack {
        FocusView(store: PreviewFixtures.store(profile: PreviewFixtures.teen))
    }
}

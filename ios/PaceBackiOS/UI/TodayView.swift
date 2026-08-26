import SwiftUI

struct TodayView: View {
    let store: AppStore
    @Binding var selectedTab: AppTab

    private var profile: LocalProfile { store.selectedProfile! }

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        "Hello, \(profile.alias)",
                        detail: welcomeDetail
                    )
                    ProfileStrip(profile: profile)
                    safetyCard
                    actionsGrid
                    engineCard
                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var welcomeDetail: String {
        switch profile.ageBand {
        case .youngChild0To5:
            "A calm, caregiver-led workspace for today."
        case .child6To12:
            "Keep today short, clear, and guided by the care team."
        case .teen13To17:
            "Choose one small step and keep guardian controls protected."
        case .adult18To64, .olderAdult65Plus:
            "Choose one small step from the clinician-guided plan."
        }
    }

    private var safetyCard: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "cross.case.fill")
                        .font(.title2)
                        .foregroundStyle(PaceBackDesign.critical)
                        .frame(width: 42, height: 42)
                        .background(PaceBackDesign.critical.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check danger signs first")
                            .font(.title3.bold())
                        Text("This age-filtered check is static, immediate, and completely bypasses AI.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    DangerSignsView(ageBand: profile.ageBand)
                } label: {
                    Label("Open emergency check", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(PaceBackDesign.critical)
                .accessibilityHint("Opens the deterministic CDC danger-sign checklist")
            }
        }
    }

    private var actionsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            TodayAction(
                number: "01",
                symbol: "timer",
                title: "Short focus",
                detail: "Start only the duration you choose."
            ) {
                selectedTab = .focus
            }
            TodayAction(
                number: "02",
                symbol: "quote.bubble",
                title: "Evidence",
                detail: "Browse sources or see a clear abstention."
            ) {
                selectedTab = .evidence
            }
            TodayAction(
                number: "03",
                symbol: "doc.text",
                title: "Care plan",
                detail: "Keep clinician decisions in charge."
            ) {
                selectedTab = .plan
            }
        }
    }

    private var engineCard: some View {
        PaceBackCard(style: store.engineAvailability.isReady ? .quiet : .caution) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        store.engineAvailability.title,
                        systemImage: "cpu.fill"
                    )
                    .font(.headline)
                    Spacer()
                    StatusPill(
                        text: store.engineAvailability.isReady ? "Local · ready" : "Fail closed",
                        kind: store.engineAvailability.isReady ? .local : .caution
                    )
                }
                Text(store.engineAvailability.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.engineAvailability.isReady {
                    Text("Model bytes came in during setup; profile data and health questions stay on this device.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PaceBackDesign.accent)
                } else {
                    Text("PaceBack will not replace a missing engine with a cloud call, fabricated citation, or generic chat response.")
                        .font(.footnote.weight(.medium))
                }
            }
        }
    }
}

private struct TodayAction: View {
    let number: String
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(number)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(PaceBackDesign.warm)
                    Spacer()
                    Image(systemName: symbol)
                        .foregroundStyle(PaceBackDesign.accent)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.secondary.opacity(0.18)) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack {
        TodayView(store: PreviewFixtures.store(), selectedTab: .constant(.today))
    }
}

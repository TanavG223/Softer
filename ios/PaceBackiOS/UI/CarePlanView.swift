import SwiftUI

struct CarePlanView: View {
    let store: AppStore
    @State private var isUnlocking = false
    @State private var controlsUnlocked = false

    private var profile: LocalProfile { store.selectedProfile! }
    private var canManage: Bool { RolePolicy.permits(.manageCarePlan, profile: profile) }

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        "The clinician plan stays in charge",
                        detail: "PaceBack does not invent restrictions, automatically advance stages, or issue clearance."
                    )
                    ProfileStrip(profile: profile)
                    planState
                    permissionCard
                    iosBoundary
                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Care plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var planState: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityHidden(true)
                Text("No clinician plan on this iOS device")
                    .font(.title3.bold())
                Text("Nothing has been inferred or prefilled. Plan items must come from a real clinician document and remain unconfirmed until an authorized person checks the source.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    StatusPill(text: "0 inferred items", kind: .local)
                    StatusPill(text: "No auto-advance", kind: .local)
                }
            }
        }
    }

    private var permissionCard: some View {
        PaceBackCard(style: canManage ? .prominent : .caution) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    canManage ? "Protected plan controls" : "View-only role",
                    systemImage: canManage ? "lock.shield.fill" : "person.badge.minus"
                )
                .font(.headline)
                Text(permissionExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if canManage {
                    Button {
                        isUnlocking = true
                        Task {
                            controlsUnlocked = await store.authorize(.manageCarePlan)
                            isUnlocking = false
                        }
                    } label: {
                        HStack {
                            if isUnlocking {
                                ProgressView()
                                Text("Authenticating…")
                            } else if controlsUnlocked {
                                Label("Controls unlocked", systemImage: "checkmark.shield.fill")
                            } else {
                                Label("Unlock plan controls", systemImage: "faceid")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isUnlocking || controlsUnlocked)
                }
            }
        }
    }

    private var iosBoundary: some View {
        PaceBackCard(style: .caution) {
            VStack(alignment: .leading, spacing: 9) {
                Label("iOS scope boundary", systemImage: "iphone")
                    .font(.headline)
                Text("PDF parsing, OCR, hybrid retrieval, and citation verification currently require the signed macOS research build. This iOS target does not pretend those capabilities are available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if controlsUnlocked {
                    Text("Authentication succeeded, but import remains disabled until a verified native iOS ingestion pipeline is implemented and evaluated.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceBackDesign.warm)
                }
            }
        }
    }

    private var permissionExplanation: String {
        guard canManage else {
            return "The active \(profile.actingRole.title.lowercased()) role cannot change this profile’s clinician plan."
        }
        if profile.ageBand.isPediatric {
            return "A parent or guardian must authenticate before pediatric plan controls open."
        }
        return "This profile owner may open plan controls. Caregiver sharing does not transfer ownership."
    }
}

#Preview("Teen view only") {
    NavigationStack {
        CarePlanView(store: PreviewFixtures.store(profile: PreviewFixtures.teen))
    }
}

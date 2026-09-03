import SwiftUI

struct WellbeingPrivacyView: View {
    let store: AppStore
    let profile: LocalProfile

    @State private var confirmsDeletion = false
    @State private var isDeleting = false

    var body: some View {
        ContentScaffold(
            "Your choices stay yours",
            subtitle: store.isGuestSession
                ? "This guest session exists only in memory. PaceBack does not save its age choice, activities, play, or check-outs."
                : "PaceBack stores a small encrypted local profile. It does not infer a mood from typing, play, time on screen, sensors, or support choices.",
            eyebrow: "YOU · PRIVACY & CONTROL",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            dataFlow
            personalizationBoundary
            gamesAndSupport
            profileControl
        }
        .navigationTitle("Privacy")
        .confirmationDialog(
            "Delete this local profile?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete encrypted profile", role: .destructive) {
                isDeleting = true
                Task {
                    _ = await store.deleteSelectedProfile()
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected profile and its local wellbeing check-outs from this Mac. This cannot be undone.")
        }
    }

    private var dataFlow: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 15) {
                Label("Local by default", systemImage: "lock.shield.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                privacyFact(
                    store.isGuestSession ? "Memory-only guest" : "Encrypted profile",
                    store.isGuestSession
                        ? "The guest profile and optional check-outs disappear when this session ends and are never sent to the encrypted repository."
                        : "Alias, age experience, role, and optional activity check-outs are stored in the profile vault on this Mac.",
                    icon: store.isGuestSession ? "eye.slash.fill" : "externaldrive.badge.checkmark"
                )
                Divider()
                privacyFact(
                    "No account or advertising profile",
                    "PaceBack does not require sign-in and does not include targeted ads or third-party behavior analytics.",
                    icon: "person.crop.circle.badge.minus"
                )
                Divider()
                privacyFact(
                    "No passive mental-state inference",
                    "Questions, typing, dwell time, game moves, sensors, and biometrics are not used to label how you feel.",
                    icon: "eye.slash.fill"
                )
            }
        }
    }

    private var personalizationBoundary: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("What optional check-outs can do")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(
                    store.isGuestSession
                        ? "A guest check-out may reorder already-available activities only during this temporary session. It is discarded when the session ends and never trains a model or creates a diagnosis."
                        : "PaceBack can retain only the chosen need, activity, one closed check-out, and its timestamp. That information may reorder already-available activities. It does not train a model, create a diagnosis, or change age and role boundaries."
                )
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choices: A little more settled · About the same · Less settled · Skip")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PaceBackDesign.accent)
                    .textSelection(.enabled)
            }
        }
    }

    private var gamesAndSupport: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { ephemeralCards }
            VStack(alignment: .leading, spacing: 14) { ephemeralCards }
        }
    }

    @ViewBuilder
    private var ephemeralCards: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Game state is session-only", systemImage: "gamecontroller")
                    .font(.headline)
                Text("Tiles, paths, hints, moves, completion, and play speed are not saved or converted into wellbeing feedback.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Support use is not feedback", systemImage: "heart.text.square")
                    .font(.headline)
                Text("Opening Support, 988, 911, a worldwide directory, or another app does not alter activity ordering. PaceBack cannot monitor what happens next.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var profileControl: some View {
        PaceBackCard(style: .caution) {
            VStack(alignment: .leading, spacing: 13) {
                Text(store.isGuestSession ? "Guest session control" : "Profile control")
                    .font(.title3.weight(.semibold))
                Text(store.isGuestSession
                    ? "Return to the encrypted workspace at any time. Temporary choices and check-outs will be discarded."
                    : (profile.ageBand.isPediatric
                        ? "macOS device-owner authentication is required for administrative changes. PaceBack cannot verify the authenticated person's family or care relationship."
                        : "The profile owner controls administrative changes. Approved caregiver access does not silently become owner access."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if store.isGuestSession {
                    Button {
                        Task { await store.returnToEncryptedWorkspace() }
                    } label: {
                        Label("End guest session", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Discards all temporary guest choices and returns to encrypted profiles")
                } else {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        if isDeleting {
                            ProgressView("Deleting encrypted profile…")
                        } else {
                            Label("Delete this local profile", systemImage: "trash")
                        }
                    }
                    .controlSize(.large)
                    .disabled(isDeleting || !RolePolicy.permits(.deleteProfile, profile: profile))
                    if !RolePolicy.permits(.deleteProfile, profile: profile) {
                        Text("This active role cannot delete the profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func privacyFact(_ title: String, _ detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(PaceBackDesign.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WellbeingAboutView: View {
    @Environment(\.openSettings) private var openSettings

    let store: AppStore
    let profile: LocalProfile

    var body: some View {
        ContentScaffold(
            "About PaceBack",
            subtitle: "A local-first research prototype for choosing a small optional activity during an ordinary stressful moment.",
            eyebrow: "YOU · PURPOSE & BOUNDARIES",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            definition
            whatItOffers
            honestBoundary
            sourceLinks
            accessibility

            HStack {
                PaceBackMark(size: 28)
                Text("PaceBack 0.2 · Research prototype · Not clinically validated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("About")
    }

    private var definition: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Label("What mental wellbeing means here", systemImage: "person.and.background.dotted")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                Text("Mental wellbeing includes emotional, psychological, and social wellbeing. It does not mean never feeling stressed or sad. PaceBack focuses on one narrow moment: making it easier to choose a small next step or reach a real person.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This definition informs the product boundary; it does not let the app assess an individual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var whatItOffers: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaceBackSectionHeader(
                "What the app offers",
                detail: "Choice before tracking",
                systemImage: "square.grid.2x2"
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                aboutFact("One obvious start", "A neutral suggestion appears before the full library.", "sparkles")
                aboutFact("Different modalities", "Notice, pause, move, connect, plan, breathe, release, or play.", "slider.horizontal.3")
                aboutFact("Finite play", "Harbor Tiles is active focus; Harbor Path is gentler focus. Both end.", "gamecontroller")
                aboutFact("Human support", "Urgent and professional-help routes stay static and model-independent.", "heart.text.square")
            }
        }
    }

    private var honestBoundary: some View {
        WellbeingBoundaryNotice()
    }

    private var sourceLinks: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("Public wellbeing context")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("These sources inform cautious product language. They do not validate PaceBack’s exact activities, games, interface, or outcomes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                sourceLink(
                    "World Health Organization · Stress",
                    URL(string: "https://www.who.int/news-room/questions-and-answers/item/stress")!
                )
                sourceLink(
                    "National Institute of Mental Health · Caring for Your Mental Health",
                    URL(string: "https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health")!
                )
                sourceLink(
                    "CDC · About Emotional Well-Being",
                    URL(string: "https://www.cdc.gov/emotional-well-being/about/index.html")!
                )
            }
        }
    }

    private var accessibility: some View {
        PaceBackCard(style: .quiet) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) { accessibilityContent }
                VStack(alignment: .leading, spacing: 14) { accessibilityContent }
            }
        }
    }

    @ViewBuilder
    private var accessibilityContent: some View {
        Image(systemName: "accessibility")
            .font(.system(size: 32))
            .foregroundStyle(PaceBackDesign.accent)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
            Text("Make PaceBack easier to use")
                .font(.title3.weight(.semibold))
            Text("Adjust text and control scale, spacing, and motion. Native controls support keyboard focus and VoiceOver, and the app follows Increase Contrast and Reduce Transparency.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 10)
        Button {
            openSettings()
        } label: {
            Label("Open Settings", systemImage: "gearshape")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(",", modifiers: .command)
    }

    private func aboutFact(_ title: String, _ detail: String, _ icon: String) -> some View {
        PaceBackCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(PaceBackDesign.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sourceLink(_ title: String, _ destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: "checkmark.seal.fill")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlSize(.large)
        .accessibilityHint("Opens the public source in your default browser without profile data")
    }
}

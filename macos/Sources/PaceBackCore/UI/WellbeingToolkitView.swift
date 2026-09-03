import SwiftUI

struct WellbeingToolkitView: View {
    let store: AppStore
    let profile: LocalProfile

    private var available: Set<WellbeingActivityID> {
        Set(store.availableWellbeingActivities)
    }

    var body: some View {
        ContentScaffold(
            "Choose what fits",
            subtitle: "Every option is short, optional, and easy to leave. The toolkit does not infer a mood or choose a treatment.",
            eyebrow: "TOOLKIT · ALL OPTIONS",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            CaregiverUseNotice(ageBand: profile.ageBand)
            if available.isEmpty {
                noAvailableActivities
            } else {
                gameSection
                activitySection(
                    "Look outward or pause",
                    detail: "Lower-demand ways to change what has your attention",
                    activities: [.orientOutside, .screenOffPause, .oneSmallStep]
                )
                activitySection(
                    "Body-based options",
                    detail: "Only within a comfortable range",
                    activities: [.gentleBreathing, .muscleRelease, .comfortableMovement]
                )
                activitySection(
                    "Human connection",
                    detail: "You choose the person and what to share",
                    activities: [.trustedConnection]
                )
            }
            WellbeingBoundaryNotice()
        }
        .navigationTitle("Toolkit")
    }

    private var noAvailableActivities: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 13) {
                Label("No activities for this profile role", systemImage: "person.badge.shield.checkmark")
                    .font(.title3.weight(.semibold))
                Text("This profile’s current role is not authorized to begin guided activities. No age or role boundary will be bypassed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    store.presentedSheet = .support
                } label: {
                    Label("Open human support", systemImage: "heart.text.square.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var gameSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaceBackSectionHeader(
                "Play without pressure",
                detail: "Two different interaction levels",
                systemImage: "gamecontroller.fill"
            )
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { gameLinks }
                VStack(alignment: .leading, spacing: 14) { gameLinks }
            }
            if !available.contains(.harborPath), !available.contains(.harborTiles) {
                PaceBackNotice(
                    "On-screen games are not offered for this age experience. The available caregiver-led options appear below.",
                    style: .local
                )
            }
        }
    }

    @ViewBuilder
    private var gameLinks: some View {
        if available.contains(.harborTiles) {
            WellbeingActivityLink(
                needID: .notSure,
                activityID: .harborTiles,
                badge: "Active focus",
                prominent: true
            )
        }
        if available.contains(.harborPath) {
            WellbeingActivityLink(
                needID: .notSure,
                activityID: .harborPath,
                badge: "Gentle focus",
                prominent: true
            )
        }
    }

    @ViewBuilder
    private func activitySection(
        _ title: String,
        detail: String,
        activities: [WellbeingActivityID]
    ) -> some View {
        let visibleActivities = activities.filter(available.contains)
        if !visibleActivities.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PaceBackSectionHeader(title, detail: detail)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 330), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(visibleActivities, id: \.self) { activityID in
                        WellbeingActivityLink(needID: .notSure, activityID: activityID)
                    }
                }
            }
        }
    }
}

struct WellbeingPlayView: View {
    let store: AppStore
    let profile: LocalProfile

    private var available: Set<WellbeingActivityID> {
        Set(store.availableWellbeingActivities)
    }

    var body: some View {
        ContentScaffold(
            "Choose your level of focus",
            subtitle: "Both games end, keep Stop and Skip visible, and do not score your performance or mental state.",
            eyebrow: "TOOLKIT · FINITE PLAY",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            CaregiverUseNotice(ageBand: profile.ageBand)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) { gameChoices }
                VStack(alignment: .leading, spacing: 18) { gameChoices }
            }

            PaceBackNotice(
                "Harbor Tiles and Harbor Path may offer a brief change of focus. Neither is a therapeutic game, attention test, cognitive-training tool, or evidence that your state changed.",
                title: "What play means here",
                style: .boundary
            )
        }
        .navigationTitle("Play")
    }

    @ViewBuilder
    private var gameChoices: some View {
        if available.contains(.harborTiles) {
            gameFeature(
                activityID: .harborTiles,
                eyebrow: "ACTIVE FOCUS",
                headline: "Fit a few pieces",
                explanation: "A more hands-on spatial task with Hint and Undo. There is no line clear, score, timer, streak, or losing."
            )
        }
        if available.contains(.harborPath) {
            gameFeature(
                activityID: .harborPath,
                eyebrow: "GENTLE FOCUS",
                headline: "Guide one lantern",
                explanation: "A lower-demand visual path with predictable clues. There is no surprise reward, failure state, or endless loop."
            )
        }
        if !available.contains(.harborTiles), !available.contains(.harborPath) {
            PaceBackCard(style: .quiet) {
                ContentUnavailableView(
                    "Games are not offered here",
                    systemImage: "display.slash",
                    description: Text("This profile’s current age or role does not offer an on-screen game. Available options remain in Toolkit.")
                )
            }
        }
    }

    private func gameFeature(
        activityID: WellbeingActivityID,
        eyebrow: String,
        headline: String,
        explanation: String
    ) -> some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 15) {
                Label(eyebrow, systemImage: activityID.systemImage)
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(PaceBackDesign.accent)
                Text(headline)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(
                    value: WellbeingLaunch(needID: .notSure, activityID: activityID)
                ) {
                    HStack {
                        Text(WellbeingPresentationCopy.openTitle(for: activityID))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

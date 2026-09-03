import SwiftUI

struct CalmHomeView: View {
    let store: AppStore
    let profile: LocalProfile

    @State private var selectedNeed: WellbeingNeedID = .notSure
    @State private var recommendation: WellbeingRecommendation?
    @State private var showsMoreChoices = false

    var body: some View {
        ContentScaffold(
            "A small next step",
            subtitle: "Choose one short option, switch activities, or stop. You do not need to name or score a feeling.",
            eyebrow: "CALM · START HERE",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            CaregiverUseNotice(ageBand: profile.ageBand)
            recentChoice
            if let recommendation, recommendation.hasEligibleActivities {
                recommendedStart(recommendation)
            } else if let recommendation {
                noEligibleActivities(recommendation)
            } else {
                PaceBackCard(style: .quiet) {
                    ContentUnavailableView(
                        "Choose an available option",
                        systemImage: "hand.point.up.left",
                        description: Text("Open Toolkit to choose an activity deliberately.")
                    )
                }
            }
            quickPlay
            DisclosureGroup("More activity choices", isExpanded: $showsMoreChoices) {
                VStack(alignment: .leading, spacing: 22) {
                    needChooser
                    playChoices
                }
                .padding(.top, 14)
            }
            .font(.headline)
            .accessibilityHint("Shows the optional need selector and second game choice")
            WellbeingBoundaryNotice()
        }
        .navigationTitle("Calm")
        .onAppear { refreshRecommendation() }
        .onChange(of: selectedNeed) { _, _ in refreshRecommendation() }
    }

    @ViewBuilder
    private var recentChoice: some View {
        if let recent = mostRecentReusableChoice {
            NavigationLink(
                value: WellbeingLaunch(needID: recent.needID, activityID: recent.activityID)
            ) {
                HStack(spacing: 12) {
                    Label("Use \(recent.activityID.title) again", systemImage: "arrow.counterclockwise.circle.fill")
                    Spacer()
                    Text(recent.activityID.durationLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Opens your most recent reusable choice. Based only on an optional check-out.")
        }
    }

    private var mostRecentReusableChoice: WellbeingFeedbackEvent? {
        guard let wellbeing = profile.wellbeing else { return nil }
        return wellbeing.feedbackEvents.last { event in
            (event.outcome == .moreSettled || event.outcome == .same)
                && event.activityID.isAvailable(for: profile)
                && !wellbeing.isCoolingDown(event.activityID, at: .now)
        }
    }

    @ViewBuilder
    private var quickPlay: some View {
        if store.availableWellbeingActivities.contains(.harborTiles) {
            VStack(alignment: .leading, spacing: 10) {
                PaceBackSectionHeader(
                    "Want something interactive?",
                    detail: "One click to finite, scoreless play",
                    systemImage: "gamecontroller.fill"
                )
                WellbeingActivityLink(
                    needID: selectedNeed,
                    activityID: .harborTiles,
                    badge: "Calm tile game",
                    prominent: true
                )
            }
        }
    }

    private func refreshRecommendation() {
        recommendation = store.recommendWellbeingActivity(for: selectedNeed, at: .now)
    }

    private func noEligibleActivities(_ recommendation: WellbeingRecommendation) -> some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 13) {
                Label("No activities for this profile role", systemImage: "person.badge.shield.checkmark")
                    .font(.title3.weight(.semibold))
                Text(recommendation.reason)
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

    private func recommendedStart(_ recommendation: WellbeingRecommendation) -> some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: recommendation.activityID.systemImage)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(PaceBackDesign.accent)
                        .frame(width: 58, height: 58)
                        .background(PaceBackDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("START A GENTLE ACTIVITY")
                            .font(.caption2.weight(.bold))
                            .tracking(0.9)
                            .foregroundStyle(PaceBackDesign.accent)
                        Text(recommendation.activityID.title)
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recommendation.activityID.shortDetail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                PaceBackNotice(
                    recommendation.reason,
                    title: recommendation.learnedFromExplicitFeedback
                        ? "Based only on your optional check-outs"
                        : "Why this option",
                    style: .local
                )

                if recommendation.canStart {
                    NavigationLink(
                        value: WellbeingLaunch(
                            needID: recommendation.needID,
                            activityID: recommendation.activityID
                        )
                    ) {
                        HStack {
                            Label(
                                WellbeingPresentationCopy.startTitle(for: recommendation.activityID),
                                systemImage: "play.fill"
                            )
                            Spacer()
                            Text(recommendation.activityID.durationLabel)
                                .font(.callout.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityHint("Opens an introduction with Stop and Skip controls")
                } else {
                    PaceBackNotice(
                        "Automatic suggestions are paused because every available activity received a recent Less settled check-out. You can stop here, return after the cooldown, or open Support.",
                        title: "No automatic choice right now",
                        style: .caution
                    )
                }

                if !recommendation.alternatives.isEmpty {
                    DisclosureGroup("Try a different kind of activity") {
                        VStack(alignment: .leading, spacing: 10) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { alternativeLinks(recommendation) }
                                VStack(alignment: .leading, spacing: 10) { alternativeLinks(recommendation) }
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.callout.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func alternativeLinks(_ recommendation: WellbeingRecommendation) -> some View {
        ForEach(recommendation.alternatives, id: \.self) { activityID in
            NavigationLink(
                value: WellbeingLaunch(needID: recommendation.needID, activityID: activityID)
            ) {
                Label(activityID.title, systemImage: activityID.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var needChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaceBackSectionHeader(
                "What would fit this moment?",
                detail: "Optional and non-diagnostic",
                systemImage: "slider.horizontal.3"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(WellbeingNeedID.allCases) { needID in
                    Button {
                        selectedNeed = needID
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: needID.systemImage)
                                .font(.headline)
                                .foregroundStyle(selectedNeed == needID ? .white : PaceBackDesign.accent)
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(needID.title)
                                    .font(.headline)
                                Text(needID.detail)
                                    .font(.caption)
                                    .foregroundStyle(selectedNeed == needID ? .white.opacity(0.88) : .secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if selectedNeed == needID {
                                Image(systemName: "checkmark.circle.fill")
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .foregroundStyle(selectedNeed == needID ? .white : .primary)
                        .background(
                            selectedNeed == needID
                                ? AnyShapeStyle(PaceBackDesign.accent)
                                : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
                            in: RoundedRectangle(cornerRadius: PaceBackDesign.smallCornerRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PaceBackDesign.smallCornerRadius)
                                .strokeBorder(
                                    selectedNeed == needID
                                        ? PaceBackDesign.accent
                                        : Color.secondary.opacity(0.18),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(needID.title)
                    .accessibilityValue(selectedNeed == needID ? "Selected" : "Not selected")
                    .accessibilityHint(needID.detail)
                }
            }
        }
    }

    @ViewBuilder
    private var playChoices: some View {
        let available = Set(store.availableWellbeingActivities)
        if available.contains(.harborTiles) || available.contains(.harborPath) {
            VStack(alignment: .leading, spacing: 14) {
                PaceBackSectionHeader(
                    "Two finite ways to play",
                    detail: "No score, timer, streak, or losing",
                    systemImage: "gamecontroller.fill"
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) { gameLinks(available) }
                    VStack(alignment: .leading, spacing: 14) { gameLinks(available) }
                }

                Text("These games may offer a brief change of focus. They are not therapy, cognitive training, or a measure of your mental state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func gameLinks(_ available: Set<WellbeingActivityID>) -> some View {
        if available.contains(.harborTiles) {
            WellbeingActivityLink(
                needID: selectedNeed,
                activityID: .harborTiles,
                badge: "Active focus"
            )
        }
        if available.contains(.harborPath) {
            WellbeingActivityLink(
                needID: selectedNeed,
                activityID: .harborPath,
                badge: "Gentle focus"
            )
        }
    }
}

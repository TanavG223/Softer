import SwiftUI

struct TodayView: View {
    let store: AppStore
    let profile: LocalProfile

    var body: some View {
        ContentScaffold(
            "Welcome back, \(profile.alias)",
            subtitle: todaySubtitle,
            eyebrow: "TODAY · \(profile.careContext.title.uppercased())",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            SafetyBoundaryNotice()
            nextStepPanel

            PaceBackSectionHeader(
                "Choose a tool",
                detail: "Each action stays inside this profile.",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
            toolRail

            PaceBackSectionHeader("Your record", systemImage: "archivebox")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    carePlanPanel
                    recentCheckInPanel
                }
                VStack(alignment: .leading, spacing: 16) {
                    carePlanPanel
                    recentCheckInPanel
                }
            }

            dangerSignPanel
        }
    }

    private var nextStepPanel: some View {
        PaceBackCard(style: .prominent, padding: 26) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 34) {
                    nextStepCopy
                    Divider().frame(height: 150)
                    planCheckpoint
                        .frame(width: 280, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 22) {
                    nextStepCopy
                    Divider()
                    planCheckpoint
                }
            }
        }
    }

    private var nextStepCopy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ONE MANAGEABLE STEP")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(PaceBackDesign.accent)
            Text(nextStepTitle)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Set the timer only from a confirmed clinician plan or professional instructions. PaceBack will never advance a stage or interpret readiness.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.selectedSection = .focus
            } label: {
                Label("Open focus session", systemImage: "timer")
            }
            .buttonStyle(.borderedProminent)
            .paceBackControlTarget()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCheckpoint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plan checkpoint", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            if let plan = profile.carePlanDraft {
                let confirmedCount = plan.restrictions.filter(\.isConfirmed).count
                StatusBadge(
                    "\(confirmedCount) of \(plan.restrictions.count) confirmed",
                    kind: plan.restrictions.allSatisfy(\.isConfirmed) ? .safe : .caution
                )
                Text(plan.sourceName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Review source items") { store.selectedSection = .carePlan }
                    .paceBackControlTarget()
            } else {
                StatusBadge("No plan imported", kind: .caution)
                Text("You can still use the workspace, but PaceBack will not invent plan limits.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open care plan") { store.selectedSection = .carePlan }
                    .paceBackControlTarget()
            }
        }
    }

    private var toolRail: some View {
        PaceBackCard(padding: 18) {
            VStack(spacing: 0) {
                PaceBackActionRow(
                    title: "Simplify a document",
                    detail: "Create a local reading aid while preserving warnings, numbers, and units.",
                    systemImage: "text.badge.minus"
                ) { store.selectedSection = .simplify }

                Divider().padding(.leading, 48)

                PaceBackActionRow(
                    title: "Ask the evidence",
                    detail: "Search only approved all-ages and \(profile.ageBand.shortTitle) sources, with citations.",
                    systemImage: "quote.bubble"
                ) { store.selectedSection = .askEvidence }

                Divider().padding(.leading, 48)

                PaceBackActionRow(
                    title: "Review entered check-ins",
                    detail: "See a descriptive record without a forecast or clinical interpretation.",
                    systemImage: "chart.xyaxis.line"
                ) { store.selectedSection = .trends }
            }
        }
    }

    private var carePlanPanel: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Care plan", systemImage: "doc.text")
                        .font(.headline)
                    Spacer()
                    Text("SOURCE OF TRUTH")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }

                if let plan = profile.carePlanDraft {
                    Text(plan.sourceName)
                        .font(.title3.weight(.medium))
                        .lineLimit(2)
                    Text("\(plan.restrictions.filter(\.isConfirmed).count) confirmed transcriptions")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No clinician plan imported")
                        .font(.title3.weight(.medium))
                    Text("Every extracted item starts unconfirmed.")
                        .foregroundStyle(.secondary)
                }

                Button("Open care plan") { store.selectedSection = .carePlan }
                    .paceBackControlTarget()
            }
        }
    }

    private var recentCheckInPanel: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Latest entry", systemImage: "list.bullet.clipboard")
                        .font(.headline)
                    Spacer()
                    StatusBadge("Descriptive only", kind: .informational)
                }

                if let recent = profile.trendEntries.last {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(recent.symptomRating)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("of 10 entered")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(recent.focusMinutes) focus minutes · \(recent.recordedAt, format: .dateTime.month().day())")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No check-ins recorded")
                        .font(.title3.weight(.medium))
                    Text("Optional entries appear after a focus session.")
                        .foregroundStyle(.secondary)
                }

                Button("Open trends") { store.selectedSection = .trends }
                    .paceBackControlTarget()
            }
        }
    }

    private var dangerSignPanel: some View {
        PaceBackCard(style: .caution) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    dangerSignCopy
                    Spacer(minLength: 20)
                    dangerSignButton
                }
                VStack(alignment: .leading, spacing: 14) {
                    dangerSignCopy
                    dangerSignButton
                }
            }
        }
    }

    private var dangerSignCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Need the emergency safety check?", systemImage: "cross.case.fill")
                .font(.headline)
            Text("This deterministic screen bypasses AI and includes age-specific CDC danger signs.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var dangerSignButton: some View {
        Button {
            store.presentedSheet = .dangerSigns
        } label: {
            Label("Check danger signs", systemImage: "arrow.right")
        }
        .buttonStyle(.bordered)
        .paceBackControlTarget()
        .accessibilityHint("Opens a deterministic check that does not use AI")
    }

    private var nextStepTitle: String {
        switch profile.ageBand {
        case .youngChild0To5: "Help today feel calm and predictable."
        case .child6To12: "Keep school and home support in sync."
        case .teen13To17: "Choose one step that feels manageable."
        case .adult18To64: "Pace the next work or daily-life task."
        case .olderAdult65Plus: "Keep today organized around the confirmed plan."
        }
    }

    private var todaySubtitle: String {
        switch profile.ageBand {
        case .youngChild0To5: "A calm caregiver view for today’s confirmed plan."
        case .child6To12: "Keep school and home support simple and coordinated."
        case .teen13To17: "Take one manageable step, with guardian controls available."
        case .adult18To64: "Plan a manageable return to daily work and activities."
        case .olderAdult65Plus: "Organize today around the confirmed clinician plan."
        }
    }
}

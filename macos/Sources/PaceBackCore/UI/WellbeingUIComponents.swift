import SwiftUI

struct WellbeingLaunch: Hashable {
    let needID: WellbeingNeedID
    let activityID: WellbeingActivityID
}

enum WellbeingPresentationCopy {
    static func startTitle(for activityID: WellbeingActivityID) -> String {
        "Start \(activityID.title)"
    }

    static func openTitle(for activityID: WellbeingActivityID) -> String {
        "Open \(activityID.title)"
    }
}

struct WellbeingBoundaryNotice: View {
    var body: some View {
        PaceBackNotice(
            "Softer offers optional activities for ordinary stressful moments. Different things work for different people, and stopping or doing nothing is always valid. It does not diagnose, treat, monitor, or guarantee an outcome.",
            title: "Choice, not treatment",
            style: .boundary
        )
    }
}

struct WellbeingActivityLink: View {
    let needID: WellbeingNeedID
    let activityID: WellbeingActivityID
    var badge: String?
    var prominent = false

    var body: some View {
        NavigationLink(value: WellbeingLaunch(needID: needID, activityID: activityID)) {
            PaceBackCard(style: prominent ? .prominent : .standard, padding: 18) {
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: activityID.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PaceBackDesign.accent)
                        .frame(width: 44, height: 44)
                        .background(PaceBackDesign.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(activityID.title)
                                .font(.headline)
                            if let badge {
                                Text(badge.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .tracking(0.6)
                                    .foregroundStyle(PaceBackDesign.accent)
                            }
                        }
                        Text(activityID.shortDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(activityID.durationLabel, systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(activityID.title), \(badge ?? "activity"), \(activityID.durationLabel)"
        )
        .accessibilityHint(activityID.shortDetail)
    }
}

struct CaregiverUseNotice: View {
    let ageBand: AgeBand

    var body: some View {
        if ageBand.isUnder13 {
            PaceBackNotice(
                "A caregiver operates this profile. Softer shows only activities permitted for this age experience; any available game is caregiver-led, and unavailable options cannot be started.",
                title: "Caregiver-operated experience",
                style: .local
            )
        }
    }
}

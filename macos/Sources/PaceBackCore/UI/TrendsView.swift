import Charts
import SwiftUI

struct TrendsView: View {
    let store: AppStore
    let profile: LocalProfile

    private var sortedEntries: [TrendEntry] {
        profile.trendEntries.sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        ContentScaffold(
            "Trends",
            subtitle: "A descriptive record of entered check-ins—not an assessment or recovery forecast.",
            eyebrow: "ENTERED VALUES · NO PREDICTION",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            SafetyBoundaryNotice()

            if profile.trendEntries.isEmpty {
                PaceBackCard(style: .quiet) {
                    ContentUnavailableView(
                        "No check-ins yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Record an optional check-in after a focus session. PaceBack will display it without interpreting recovery.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            } else {
                enteredValueSummary
                chartPanel
                accessibleEntryList
            }
        }
    }

    private var enteredValueSummary: some View {
        PaceBackCard(style: .prominent, padding: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { horizontalSummaryValues }
                VStack(alignment: .leading, spacing: 14) { verticalSummaryValues }
            }
        }
    }

    @ViewBuilder
    private var horizontalSummaryValues: some View {
        EnteredValue(
            label: "Entries",
            value: "\(profile.trendEntries.count)",
            detail: "Recorded locally",
            systemImage: "list.number"
        )
        Divider().frame(height: 54).padding(.horizontal, 18)
        EnteredValue(
            label: "Latest rating",
            value: "\(profile.trendEntries.last?.symptomRating ?? 0) / 10",
            detail: "User-entered value",
            systemImage: "slider.horizontal.3"
        )
        Divider().frame(height: 54).padding(.horizontal, 18)
        EnteredValue(
            label: "Recorded focus",
            value: "\(profile.trendEntries.reduce(0) { $0 + $1.focusMinutes }) min",
            detail: "Across saved entries",
            systemImage: "timer"
        )
        Divider().frame(height: 54).padding(.horizontal, 18)
        VStack(alignment: .leading, spacing: 7) {
            StatusBadge("Descriptive only", kind: .informational)
            Text("No score or trajectory is calculated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var verticalSummaryValues: some View {
        EnteredValue(
            label: "Entries",
            value: "\(profile.trendEntries.count)",
            detail: "Recorded locally",
            systemImage: "list.number"
        )
        Divider()
        EnteredValue(
            label: "Latest rating",
            value: "\(profile.trendEntries.last?.symptomRating ?? 0) / 10",
            detail: "User-entered value",
            systemImage: "slider.horizontal.3"
        )
        Divider()
        EnteredValue(
            label: "Recorded focus",
            value: "\(profile.trendEntries.reduce(0) { $0 + $1.focusMinutes }) min",
            detail: "Across saved entries",
            systemImage: "timer"
        )
        Divider()
        VStack(alignment: .leading, spacing: 7) {
            StatusBadge("Descriptive only", kind: .informational)
            Text("No score or trajectory is calculated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chartPanel: some View {
        PaceBackCard(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Entered symptom ratings")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Dots are individual entries; the line only connects them for readability.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("0–10 entered scale", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PaceBackDesign.calmBlue)
                }

                Chart(profile.trendEntries) { entry in
                    LineMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Entered rating", entry.symptomRating)
                    )
                    .foregroundStyle(PaceBackDesign.calmBlue)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Entered rating", entry.symptomRating)
                    )
                    .foregroundStyle(PaceBackDesign.calmBlue)
                    .symbol(.circle)
                    .symbolSize(68)
                }
                .chartYScale(domain: 0...10)
                .chartYAxisLabel("Entered rating (0–10)")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10]) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel()
                    }
                }
                .frame(height: 280)
                .accessibilityHidden(true)

                PaceBackNotice(
                    "PaceBack does not interpret whether the connected line is improving, worsening, or stable.",
                    style: .boundary
                )
            }
        }
    }

    private var accessibleEntryList: some View {
        PaceBackCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                PaceBackSectionHeader(
                    "Accessible entry list",
                    detail: "Newest first",
                    systemImage: "list.bullet.rectangle"
                )

                ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            entryDate(entry)
                                .frame(width: 150, alignment: .leading)
                            entryValue(entry)
                            Spacer()
                            Text("\(entry.focusMinutes) focus min")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            entryDate(entry)
                            entryValue(entry)
                            Text("\(entry.focusMinutes) focus minutes")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(entry.recordedAt.formatted(date: .long, time: .omitted)). Entered rating \(entry.symptomRating) out of 10. \(entry.focusMinutes) focus minutes."
                    )

                    if index < sortedEntries.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func entryDate(_ entry: TrendEntry) -> some View {
        Text(entry.recordedAt, format: .dateTime.month().day().year())
            .font(.callout.weight(.semibold))
    }

    private func entryValue(_ entry: TrendEntry) -> some View {
        Text("Rating \(entry.symptomRating) of 10")
            .font(.callout.monospacedDigit())
    }
}

private struct EnteredValue: View {
    let label: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

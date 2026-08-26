import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CarePlanView: View {
    let store: AppStore
    let profile: LocalProfile

    @State private var showImporter = false
    @State private var isImporting = false
    @State private var includeRestrictions = true
    @State private var includeSessionEntries = true
    @State private var includeNotes = false
    @State private var copiedReport = false

    private var canConfirm: Bool {
        RolePolicy.permits(.manageCarePlan, profile: profile)
    }

    private var canImport: Bool {
        RolePolicy.permits(.importDocuments, profile: profile)
    }

    var body: some View {
        ContentScaffold(
            "Care Plan",
            subtitle: "Extracted text stays a draft until an authorized person confirms it against the original.",
            eyebrow: "SOURCE-CITED · HUMAN CONFIRMED",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            SafetyBoundaryNotice()

            CarePlanProcessRail()

            PaceBackCard(style: .prominent) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) { importControls }
                    VStack(alignment: .leading, spacing: 12) { importControls }
                }
            }

            if let draft = profile.carePlanDraft {
                PaceBackCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.sourceName)
                                    .font(.title3.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)
                                Text("Imported \(draft.importedAt, format: .dateTime.month().day().year())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                "\(draft.restrictions.filter(\.isConfirmed).count) of \(draft.restrictions.count) confirmed",
                                kind: draft.restrictions.allSatisfy(\.isConfirmed) ? .safe : .caution
                            )
                        }

                        PaceBackNotice(
                            "Compare every item with the original PDF. Confirmation records transcription—not medical agreement or clearance.",
                            style: .boundary
                        )

                        VStack(spacing: 0) {
                            ForEach(Array(draft.restrictions.enumerated()), id: \.element.id) { index, restriction in
                                Button {
                                    Task {
                                        await store.setRestrictionConfirmed(
                                            id: restriction.id,
                                            confirmed: !restriction.isConfirmed
                                        )
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 13) {
                                        Image(systemName: restriction.isConfirmed ? "checkmark.square.fill" : "square")
                                            .font(.title3)
                                            .foregroundStyle(restriction.isConfirmed ? PaceBackDesign.accent : .secondary)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(restriction.text)
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text("SOURCE PAGE \(restriction.page)")
                                                .font(.caption2.monospaced().weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .paceBackControlTarget()
                                .disabled(!canConfirm)
                                .accessibilityLabel(
                                    "\(restriction.isConfirmed ? "Confirmed" : "Unconfirmed") item. \(restriction.text). Source page \(restriction.page)"
                                )
                                .accessibilityHint(canConfirm ? "Toggles transcription confirmation" : "Current role cannot confirm plan items")

                                if index < draft.restrictions.count - 1 {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }

                        if canImport && !canConfirm {
                            PaceBackNotice(
                                "An approved caregiver may import a plan, but the profile owner must confirm extracted items.",
                                style: .local
                            )
                        }
                    }
                }
            } else {
                PaceBackCard(style: .quiet) {
                    ContentUnavailableView(
                        "No clinician plan imported",
                        systemImage: "doc.badge.plus",
                        description: Text("PaceBack can extract possible restrictions locally from a text or scanned PDF. Every item starts unconfirmed.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 210)
                }
            }

            PaceBackCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reportTitle).font(.title3.weight(.semibold))
                            Text("Selected facts only · never an AI conclusion")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .foregroundStyle(PaceBackDesign.accent)
                            .accessibilityHidden(true)
                    }
                    Toggle("Confirmed plan items", isOn: $includeRestrictions)
                        .paceBackControlTarget()
                    Toggle("Focus-session entries", isOn: $includeSessionEntries)
                        .paceBackControlTarget()
                    Toggle("User-entered notes", isOn: $includeNotes)
                        .paceBackControlTarget()
                    HStack {
                        Button {
                            copyReport()
                        } label: {
                            Label("Copy selected report", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .paceBackControlTarget()
                        .disabled(!RolePolicy.permits(.exportData, profile: profile))
                        if copiedReport {
                            Label("Copied locally", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(PaceBackDesign.accent)
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            isImporting = true
            Task {
                _ = await store.importCarePlan(from: url)
                isImporting = false
            }
        }
    }

    private var reportTitle: String {
        switch profile.ageBand {
        case .youngChild0To5, .child6To12, .teen13To17: "Caregiver / school clipboard report"
        case .adult18To64: "Workplace / caregiver clipboard report"
        case .olderAdult65Plus: "Caregiver clipboard report"
        }
    }

    @ViewBuilder
    private var importControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bring in the clinician’s source document")
                .font(.title3.weight(.semibold))
            Text("PDFKit and OCR run locally; extracted restrictions remain unconfirmed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)

        Button {
            showImporter = true
        } label: {
            Label("Import clinician PDF", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .paceBackControlTarget()
        .disabled(!canImport || isImporting)

        if isImporting {
            ProgressView("Reading locally…")
                .controlSize(.small)
                .accessibilityHint("No document data is transmitted")
        }

        if !canImport {
            if profile.ageBand == .teen13To17 && profile.actingRole == .teenUser {
                Button {
                    Task { _ = await store.switchActingRole(to: .guardian) }
                } label: {
                    Label("Unlock guardian controls…", systemImage: "lock.open")
                }
                .paceBackControlTarget()
                .help("Authenticate with this Mac to manage the plan or copy a selected-field report")
            } else {
                Label("Authorized role required", systemImage: "lock.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyReport() {
        Task {
            guard await store.authorize(.exportData) else { return }
            var sections = [
                "PaceBack factual report for alias: \(profile.alias)",
                "Age band: \(profile.ageBand.title)",
                "Generated locally: \(Date.now.formatted(date: .abbreviated, time: .standard))"
            ]
            if includeRestrictions, let draft = profile.carePlanDraft {
                let confirmed = draft.restrictions.filter(\.isConfirmed)
                sections.append("Confirmed transcriptions:\n" + confirmed.map { "- \($0.text) (source page \($0.page))" }.joined(separator: "\n"))
            }
            if includeSessionEntries {
                sections.append("Session entries:\n" + profile.trendEntries.map {
                    "- \($0.recordedAt.formatted(date: .numeric, time: .omitted)): \($0.focusMinutes) minutes; entered rating \($0.symptomRating)/10"
                }.joined(separator: "\n"))
            }
            if includeNotes {
                sections.append("User-entered notes:\n" + profile.trendEntries.compactMap { $0.note.isEmpty ? nil : "- \($0.note)" }.joined(separator: "\n"))
            }
            sections.append("Research prototype. This report contains no diagnosis, treatment recommendation, prognosis, or clearance.")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
            copiedReport = true
        }
    }
}

private struct CarePlanProcessRail: View {
    private let steps = [
        ("01", "Import", "PDF or scan"),
        ("02", "Locate", "Page-cited text"),
        ("03", "Compare", "Check original"),
        ("04", "Confirm", "Authorized person")
    ]

    var body: some View {
        PaceBackCard(style: .quiet, padding: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { processSteps }
                VStack(alignment: .leading, spacing: 10) { processSteps }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var processSteps: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            HStack(spacing: 9) {
                Text(step.0)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(index == 0 ? PaceBackDesign.warm : PaceBackDesign.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.1).font(.callout.weight(.semibold))
                    Text(step.2).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if index < steps.count - 1 {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .accessibilityHidden(true)
            }
        }
    }
}

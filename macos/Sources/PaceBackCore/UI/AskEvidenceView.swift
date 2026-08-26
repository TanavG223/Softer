import SwiftUI

struct AskEvidenceView: View {
    let store: AppStore
    let profile: LocalProfile
    let engineConnected: Bool

    @State private var model = AskEvidenceModel()
    @State private var speechReader = SpeechReader()

    private var allowsFreeform: Bool {
        RolePolicy.permits(.useFreeformAI, profile: profile)
    }

    var body: some View {
        @Bindable var model = model

        ContentScaffold(
            "Ask Evidence",
            subtitle: "Age-filtered retrieval, inspectable citations, and a clear abstention when support is missing.",
            eyebrow: "LOCAL AI · BOUNDED RAG",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile, evidenceFiltered: true)
            SafetyBoundaryNotice()

            if !engineConnected {
                PaceBackNotice(
                    "Evidence Q&A is unavailable. PaceBack will not simulate an answer or fall back to a cloud service.",
                    title: "Private evidence engine unavailable",
                    style: .error
                )
            }

            questionDesk(model: model)
            answerContent
        }
        .onDisappear {
            model.cancel(profileID: profile.id, engine: store.aiEngine)
            speechReader.stop()
        }
    }

    private func questionDesk(model: AskEvidenceModel) -> some View {
        @Bindable var model = model

        return PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Question desk")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(questionGuidance)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    StatusBadge(
                        engineConnected ? "Engine ready" : "Engine offline",
                        kind: engineConnected ? .safe : .caution
                    )
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("START WITH A SAFE QUESTION")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250, maximum: 520), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(suggestedQuestions, id: \.self) { question in
                            Button {
                                model.question = question
                            } label: {
                                Text(question)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                                .buttonStyle(.bordered)
                                .paceBackControlTarget()
                        }
                    }
                }

                if allowsFreeform {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your question")
                            .font(.headline)
                        TextEditor(text: $model.question)
                            .font(.body)
                            .frame(minHeight: 112)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                            }
                            .accessibilityLabel("Evidence question")
                            .accessibilityHint("Ask about recovery support; danger signs use the separate deterministic safety check")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Selected caregiver question")
                            .font(.headline)
                        Text(model.question.isEmpty ? "Choose one of the caregiver-safe questions above." : model.question)
                            .foregroundStyle(model.question.isEmpty ? .secondary : .primary)
                            .padding(13)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                        Label("Freeform AI is disabled for under-13 profiles.", systemImage: "lock.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(PaceBackDesign.accent)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { askControls(model: model) }
                    VStack(alignment: .leading, spacing: 10) { askControls(model: model) }
                }
            }
        }
    }

    @ViewBuilder
    private func askControls(model: AskEvidenceModel) -> some View {
        Button {
            model.ask(profile: profile, engine: store.aiEngine)
        } label: {
            Label("Ask local evidence", systemImage: "arrow.up.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .paceBackControlTarget()
        .disabled(!engineConnected || model.question.isEmpty || model.state == .loading)
        .keyboardShortcut(.return, modifiers: [.command])

        if model.state == .loading {
            ProgressView("Retrieving and checking sources…")
                .controlSize(.small)
            Button("Cancel") {
                model.cancel(profileID: profile.id, engine: store.aiEngine)
            }
            .paceBackControlTarget()
        } else {
            Label("No network tools · frozen model", systemImage: "lock.shield")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var answerContent: some View {
        switch model.state {
        case .idle:
            EvidenceProcessRail()

        case .loading:
            PaceBackCard(style: .quiet) {
                VStack(alignment: .leading, spacing: 12) {
                    PaceBackSectionHeader("Building a bounded answer", systemImage: "text.magnifyingglass")
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Retrieving, reranking, and verifying local evidence")
                    Text("PaceBack is retrieving from the permitted age scopes, removing duplicates, reranking passages, and checking citation support.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            PaceBackNotice(
                message,
                title: "No evidence answer was returned",
                style: .error
            )

        case .loaded(let answer):
            answerPanel(answer)
        }
    }

    private func answerPanel(_ answer: EvidenceAnswer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PaceBackCard(padding: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Evidence answer")
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("Run \(String(answer.runID.prefix(8)))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        supportBadge(answer.supportStatus)
                    }

                    Text(answer.answer)
                        .font(.body)
                        .lineSpacing(store.preferences.comfortableSpacing ? 6 : 2)
                        .textSelection(.enabled)

                    if store.preferences.readAnswersAloud {
                        Button {
                            speechReader.isSpeaking ? speechReader.stop() : speechReader.speak(answer.answer)
                        } label: {
                            Label(
                                speechReader.isSpeaking ? "Stop reading" : "Read answer aloud",
                                systemImage: speechReader.isSpeaking ? "stop.fill" : "speaker.wave.2"
                            )
                        }
                        .paceBackControlTarget()
                    }

                    if answer.citations.isEmpty {
                        PaceBackNotice(
                            "No unsupported medical claim is displayed as sourced. Review the answer’s support status above.",
                            style: .local
                        )
                    }
                }
            }

            if !answer.citations.isEmpty {
                PaceBackSectionHeader(
                    "Evidence trail",
                    detail: "\(answer.citations.count) locatable source \(answer.citations.count == 1 ? "passage" : "passages")",
                    systemImage: "checkmark.seal"
                )
                PaceBackCard(padding: 20) {
                    VStack(spacing: 0) {
                        ForEach(Array(answer.citations.enumerated()), id: \.element.id) { index, citation in
                            CitationView(citation: citation, index: index + 1)
                            if index < answer.citations.count - 1 {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }

            runDetails(answer)
        }
    }

    private func runDetails(_ answer: EvidenceAnswer) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                    GridRow { detailLabel("Route"); detailValue(answer.route) }
                    GridRow { detailLabel("Stop reason"); detailValue(answer.stopReason) }
                    GridRow { detailLabel("Retrieval rounds"); detailValue("\(answer.usage.retrievalRounds)") }
                    GridRow { detailLabel("Retrieved tokens"); detailValue("\(answer.usage.retrievedTokens)") }
                    GridRow { detailLabel("Input / output tokens"); detailValue("\(answer.usage.inputTokens) / \(answer.usage.outputTokens)") }
                    GridRow {
                        detailLabel("Latency")
                        detailValue("\(answer.usage.latencyMS.formatted(.number.precision(.fractionLength(0)))) ms")
                    }
                }
                PaceBackNotice(
                    "These values explain how the local pipeline ran. They are not a confidence score or clinical assessment.",
                    style: .boundary
                )
            }
            .padding(.top, 12)
        } label: {
            Label("Inspect run details", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: PaceBackDesign.smallCornerRadius))
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text).font(.callout.weight(.semibold))
    }

    private func detailValue(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func supportBadge(_ status: SupportStatus) -> some View {
        switch status {
        case .verified: StatusBadge("Citation support verified", kind: .safe)
        case .partial: StatusBadge("Partially supported", kind: .caution)
        case .insufficientInformation: StatusBadge("Not enough information", kind: .informational)
        case .dangerSignDetected: StatusBadge("Safety gate", kind: .caution)
        case .cancelled: StatusBadge("Cancelled", kind: .informational)
        }
    }

    private var questionGuidance: String {
        profile.ageBand.isUnder13
            ? "Choose a caregiver-safe prompt; unrestricted medical chat is intentionally unavailable."
            : "Ask about organizing care, school, work, daily life, or questions for a professional."
    }

    private var suggestedQuestions: [String] {
        switch profile.ageBand {
        case .youngChild0To5:
            ["What should a caregiver track for the next clinician visit?", "How can I organize a calm home routine?"]
        case .child6To12:
            ["What school adjustments does CDC describe?", "How can caregivers and school staff coordinate notes?"]
        case .teen13To17:
            ["What does CDC say about returning to school?", "How can I describe symptoms to a school nurse?"]
        case .adult18To64:
            ["What return-to-work adjustments does CDC describe?", "How can I prepare questions for my clinician?"]
        case .olderAdult65Plus:
            ["How can a caregiver help organize clinician instructions?", "What should I bring to a follow-up visit?"]
        }
    }
}

private struct EvidenceProcessRail: View {
    private let steps = [
        ("01", "Retrieve", "Sparse + dense"),
        ("02", "Rerank", "Local MiniLM"),
        ("03", "Reduce", "Protect key facts"),
        ("04", "Verify", "Citations or abstain")
    ]

    var body: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("HOW AN ANSWER EARNS ITS PLACE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { railSteps }
                    VStack(alignment: .leading, spacing: 12) { railSteps }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var railSteps: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            HStack(spacing: 9) {
                Text(step.0)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(index == 0 ? PaceBackDesign.warm : PaceBackDesign.accent)
                VStack(alignment: .leading, spacing: 2) {
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
                    .padding(.horizontal, 6)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct CitationView: View {
    let citation: SourceCitation
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(PaceBackDesign.accent.opacity(0.12))
                Text("\(index)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(PaceBackDesign.accent)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(PaceBackDesign.accent)
                        .accessibilityHidden(true)
                    if let url = citation.url {
                        Link(citation.title, destination: url)
                    } else {
                        Text(citation.title).fontWeight(.semibold)
                    }
                    if let page = citation.page {
                        Text("Page \(page)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("“\(citation.quote)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("LOCATOR · \(citation.sourceID)")
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Source \(index), \(citation.title)\(citation.page.map { ", page \($0)" } ?? ""). \(citation.quote). Locator \(citation.sourceID)"
        )
    }
}

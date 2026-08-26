import SwiftUI

struct EvidenceView: View {
    let store: AppStore

    @State private var question = ""
    @FocusState private var questionFocused: Bool

    private var profile: LocalProfile { store.selectedProfile! }

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        "Ask cited evidence",
                        detail: "Private local search finds age-matched passages, reranks them on this device, and abstains when support is not strong enough."
                    )
                    ProfileStrip(profile: profile)
                    availabilityCard
                    questionCard
                    sourceCatalog
                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Evidence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availabilityCard: some View {
        PaceBackCard(style: store.engineAvailability.isReady ? .quiet : .caution) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Label(store.engineAvailability.title, systemImage: "cpu")
                        .font(.headline)
                    Spacer()
                    StatusPill(
                        text: store.engineAvailability.isReady ? "Ready offline" : "No cloud fallback",
                        kind: store.engineAvailability.isReady ? .local : .caution
                    )
                }
                Text(store.engineAvailability.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Your question remains on this device. It is never sent to a public model, search service, or model-training system.")
                    .font(.footnote.weight(.medium))
            }
        }
    }

    private var questionCard: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("Ask the local evidence library")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Ask about concussion recovery guidance. PaceBack returns a short cited answer or an explicit abstention—not diagnosis, treatment, or clearance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Ask about the evidence…", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .focused($questionFocused)
                    .accessibilityHint("This text stays on the device")
                Button {
                    questionFocused = false
                    Task { await store.attemptEvidence(question: question) }
                } label: {
                    HStack {
                        if store.evidenceAttempt == .checking {
                            ProgressView()
                            Text("Searching local sources…")
                        } else {
                            Label("Check on-device evidence", systemImage: "checkmark.shield")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.evidenceAttempt == .checking)
                .accessibilityIdentifier("evidence.ask")

                if case .answer(let response) = store.evidenceAttempt {
                    sourceLinkedAnswer(response)
                } else if case .abstention(let reason) = store.evidenceAttempt {
                    abstentionPanel(reason)
                } else if case .unavailable(let reason) = store.evidenceAttempt {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Evidence unavailable", systemImage: "nosign")
                            .font(.headline)
                            .foregroundStyle(PaceBackDesign.warm)
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PaceBackDesign.warm.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func sourceLinkedAnswer(_ response: EvidenceResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Source-linked local result", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(PaceBackDesign.accent)
            Text(response.answer)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let milliseconds = response.localInferenceMilliseconds {
                Text("Completed locally in \(milliseconds.formatted()) ms · no cloud request")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text("Sources")
                .font(.subheadline.weight(.semibold))
            ForEach(response.citations) { citation in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("[\(citation.number)] \(citation.title)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Link(destination: citation.url) {
                            Label("Open", systemImage: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .accessibilityLabel("Open source \(citation.number), \(citation.title)")
                    }
                    Text("“\(citation.exactQuote)”")
                        .font(.footnote)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(citation.locator)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Excerpt hash \(citation.contentHash.prefix(12))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
            }
            Text("Source-linked means each excerpt and locator were checked against the bundled corpus; it does not mean the result is medically verified. Use it to support a conversation with a clinician, not to make a medical decision.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceBackDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func abstentionPanel(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("PaceBack is pausing here", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(PaceBackDesign.warm)
            Text(reason)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Try a narrower evidence question, or bring this question to a clinician. No cloud fallback was used.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceBackDesign.warm.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var sourceCatalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trusted source catalog")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(EvidenceSource.trusted) { source in
                Link(destination: source.url) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(PaceBackDesign.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(source.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.17)) }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the source in the default browser")
            }
        }
    }
}

#Preview {
    NavigationStack {
        EvidenceView(store: PreviewFixtures.store())
    }
}

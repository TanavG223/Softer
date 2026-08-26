import AppKit
import SwiftUI

struct SimplifyView: View {
    let store: AppStore
    let profile: LocalProfile

    @State private var sourceText = ""
    @State private var result: SimplificationResult?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copiedResult = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        ContentScaffold(
            "Simplify",
            subtitle: "Create a clearer reading aid while keeping the original available for comparison.",
            eyebrow: "LOCAL READING AID · PRESERVATION CHECKED",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            SafetyBoundaryNotice()
            workflowRail
            sourcePanel
            outputContent
        }
        .onDisappear { task?.cancel() }
    }

    private var workflowRail: some View {
        PaceBackCard(style: .quiet, padding: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { workflowSteps }
                VStack(alignment: .leading, spacing: 10) { workflowSteps }
            }
        }
    }

    @ViewBuilder
    private var workflowSteps: some View {
        SimplifyStep(number: "01", title: "Paste", detail: "Text stays local")
        Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        SimplifyStep(number: "02", title: "Reduce", detail: "Choose reading detail")
        Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        SimplifyStep(number: "03", title: "Compare", detail: "Check protected facts")
    }

    private var sourcePanel: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { editorHeader }
                    VStack(alignment: .leading, spacing: 10) { editorHeader }
                }

                TextEditor(text: $sourceText)
                    .font(.body)
                    .frame(minHeight: 220)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                    }
                    .accessibilityLabel("Original text to simplify")
                    .accessibilityHint("Paste text that you will compare with the resulting reading aid")

                HStack {
                    Label("\(sourceText.count) characters", systemImage: "textformat.abc")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("Never sent off this Mac", systemImage: "wifi.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PaceBackDesign.accent)
                }
                .accessibilityElement(children: .contain)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { simplifyControls }
                    VStack(alignment: .leading, spacing: 10) { simplifyControls }
                }
            }
        }
    }

    @ViewBuilder
    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Original text", systemImage: "doc.plaintext")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Warnings, numbers, units, names, and negations must survive reduction.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 14)
        Picker("Reading detail", selection: Bindable(store.preferences).readingMode) {
            ForEach(ReadingMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 330)
        .accessibilityHint("Controls the maximum amount of detail in the reading aid")
    }

    @ViewBuilder
    private var simplifyControls: some View {
        Button {
            simplify()
        } label: {
            Label("Create reading aid", systemImage: "text.badge.minus")
        }
        .buttonStyle(.borderedProminent)
        .paceBackControlTarget()
        .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        .keyboardShortcut(.return, modifiers: [.command])

        if isWorking {
            ProgressView("Checking preserved details…")
                .controlSize(.small)
            Button("Cancel") {
                task?.cancel()
                task = nil
                isWorking = false
            }
            .paceBackControlTarget()
        } else {
            Text("Mode: \(store.preferences.readingMode.title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        if let result {
            PaceBackSectionHeader("Reading aid", detail: "Compare with the original above.", systemImage: "text.quote")
            PaceBackCard(padding: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        StatusBadge(
                            result.usedFoundationModel ? "Apple on-device model" : "Extractive safety fallback",
                            kind: .informational
                        )
                        Spacer()
                        Text("\(result.originalCharacterCount) → \(result.outputCharacterCount) characters")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(result.text)
                        .font(.body)
                        .lineSpacing(store.preferences.comfortableSpacing ? 6 : 2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { resultActions(result) }
                        VStack(alignment: .leading, spacing: 10) { resultActions(result) }
                    }
                }
            }
        } else if isWorking {
            PaceBackCard(style: .quiet) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reading aid")
                        .font(.headline)
                    Text("The result will appear here without moving the original text.")
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 18)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 420, height: 18)
                }
                .redacted(reason: .placeholder)
            }
        } else {
            PaceBackNotice(
                "The reading aid is not a new care plan. Check every restriction, warning, number, and unit against the original before relying on it.",
                title: "Comparison is part of the workflow",
                style: .local
            )
        }

        if let errorMessage {
            PaceBackNotice(
                errorMessage,
                title: "A safe reading aid could not be created",
                style: .error
            )
            .accessibilityLabel("Simplification error: \(errorMessage)")
        }
    }

    @ViewBuilder
    private func resultActions(_ result: SimplificationResult) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.text, forType: .string)
            copiedResult = true
        } label: {
            Label("Copy reading aid", systemImage: "doc.on.doc")
        }
        .paceBackControlTarget()

        if copiedResult {
            Label("Copied locally", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(PaceBackDesign.accent)
        }

        Spacer(minLength: 0)

        Label("Original remains unchanged", systemImage: "lock.doc")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func simplify() {
        task?.cancel()
        isWorking = true
        errorMessage = nil
        result = nil
        copiedResult = false
        let source = sourceText
        let mode = store.preferences.readingMode
        let service = store.simplifier
        task = Task {
            do {
                let response = try await service.simplify(source, readingMode: mode)
                guard !Task.isCancelled else { return }
                result = response
                isWorking = false
            } catch is CancellationError {
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}

private struct SimplifyStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Text(number)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(number == "01" ? PaceBackDesign.warm : PaceBackDesign.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

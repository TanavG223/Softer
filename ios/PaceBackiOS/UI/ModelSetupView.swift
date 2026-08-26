import SwiftUI

private enum ModelSetupConfirmation: String, Identifiable {
    case delete
    case reinstall

    var id: String { rawValue }
}

struct ModelSetupView: View {
    let store: AppStore
    let isRequired: Bool

    @State private var networkPolicy: ModelPackNetworkPolicy = .wifiOnly
    @State private var confirmation: ModelSetupConfirmation?

    var body: some View {
        Group {
            if isRequired {
                NavigationStack { setupContent }
            } else {
                setupContent
            }
        }
        .task {
            if !store.modelPackStatus.isWorking {
                await store.refreshModelPackStatus()
            }
        }
        .alert(item: $confirmation) { item in
            switch item {
            case .delete:
                Alert(
                    title: Text("Delete private AI models?"),
                    message: Text(
                        "This removes 157,716,998 verified model bytes from this device. Profiles and clinician-plan data are not removed. Evidence search stays unavailable until you reinstall."
                    ),
                    primaryButton: .destructive(Text("Delete models")) {
                        Task { await store.deleteModelPack() }
                    },
                    secondaryButton: .cancel()
                )
            case .reinstall:
                Alert(
                    title: Text("Verify a fresh model pack?"),
                    message: Text(
                        "PaceBack will download and verify a new staged copy before replacing the current pack. Keep PaceBack open until Ready."
                    ),
                    primaryButton: .default(Text("Reinstall")) {
                        Task {
                            await store.installModelPack(
                                networkPolicy: networkPolicy,
                                force: true
                            )
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var setupContent: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    stagePath
                    statusPanel
                    if !store.modelPackStatus.isWorking {
                        whatThisUnlocks
                        modelExplanation
                    }
                    privacyReceipt
                    safetyBoundary
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Private AI setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PaceBackMark(size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ONE SMALL STEP")
                        .font(.caption.bold())
                        .tracking(1.1)
                        .foregroundStyle(PaceBackDesign.accent)
                    Text("Ready offline after setup")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text("Bring PaceBack’s private AI onto this iPhone")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Download frozen model weights and tokenizers once, verify every byte, then search age-matched evidence without sending a health question away.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("One small step is enough today.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaceBackDesign.warm)
        }
    }

    private var stagePath: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("THREE QUIET STAGES")
                    .font(.caption2.bold())
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 6) {
                    stage("1", "Download", symbol: "arrow.down.circle.fill", state: downloadStageState)
                    stageConnector(completed: downloadStageState == .complete)
                    stage("2", "Verify", symbol: "checkmark.shield.fill", state: verifyStageState)
                    stageConnector(completed: verifyStageState == .complete)
                    stage("3", "Ready offline", symbol: "iphone.and.arrow.forward", state: readyStageState)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stageAccessibilityLabel)
    }

    @ViewBuilder
    private var statusPanel: some View {
        switch store.modelPackStatus {
        case .checking:
            PaceBackCard(style: .prominent) {
                Label("Checking local model storage…", systemImage: "externaldrive.badge.checkmark")
                    .font(.headline)
                    .accessibilityLabel("Checking local model storage")
            }

        case .notInstalled:
            installChoice(title: "Install private evidence search", buttonTitle: "Download and verify")

        case .preparing(let capacity):
            PaceBackCard(style: .prominent) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Preparing protected storage", systemImage: "internaldrive.fill")
                        .font(.headline)
                    capacityRow(capacity)
                    Text("No network request includes a profile, alias, symptom, question, or care-plan field.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        case .downloading(let progress):
            downloadProgress(progress)

        case .verifying(let completed, let total):
            verificationProgress(completed: completed, total: total)

        case .paused(let progress):
            installChoice(
                title: progress.receivedBytes > 0 ? "Download paused safely" : "Download cancelled",
                buttonTitle: progress.receivedBytes > 0 ? "Resume download" : "Try download again",
                progress: progress
            )

        case .ready(let receipt):
            readyPanel(receipt)

        case .failed(let failure):
            failurePanel(failure)
        }
    }

    private func installChoice(
        title: String,
        buttonTitle: String,
        progress: ModelPackProgress? = nil
    ) -> some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: "arrow.down.to.line.compact")
                    .font(.title2.bold())
                Text("157,716,998 bytes · about 151 MiB to download")
                    .font(.headline)
                    .foregroundStyle(PaceBackDesign.accent)
                if let progress, progress.receivedBytes > 0 {
                    Text("\(byteText(progress.receivedBytes)) already verified or resumable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Choose network use")
                        .font(.headline)
                    Picker("Choose network use", selection: $networkPolicy) {
                        ForEach(ModelPackNetworkPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("modelSetup.networkPolicy")
                    Text(networkPolicy.detail)
                        .font(.footnote)
                        .foregroundStyle(networkPolicy == .wifiAndCellular ? PaceBackDesign.warm : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let capacity = store.modelPackCapacity {
                    capacityRow(capacity)
                } else {
                    Label("Free space will be checked before download", systemImage: "internaldrive")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Keep PaceBack open until Ready. Cancel saves resumable transfer data when the server provides it; partial files are never activated.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        await store.installModelPack(networkPolicy: networkPolicy)
                    }
                } label: {
                    Label(buttonTitle, systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.modelPackCapacity?.hasEnoughSpace == false)
                .accessibilityIdentifier("modelSetup.install")
                .accessibilityHint("Downloads only the four pinned model artifacts, then verifies and activates them")
            }
        }
    }

    private func downloadProgress(_ progress: ModelPackProgress) -> some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Downloading locally", systemImage: "arrow.down.circle.fill")
                        .font(.title2.bold())
                    Spacer()
                    StatusPill(text: percentText(progress.fractionCompleted), kind: .local)
                }

                ProgressView(value: progress.fractionCompleted) {
                    Text("Total model pack")
                } currentValueLabel: {
                    Text("\(byteText(progress.receivedBytes)) of 157,716,998 bytes")
                }
                .tint(PaceBackDesign.accent)
                .accessibilityLabel("Total model download")
                .accessibilityValue("\(percentText(progress.fractionCompleted)), \(progress.receivedBytes) of 157,716,998 bytes")

                VStack(spacing: 12) {
                    ForEach(progress.artifacts) { artifact in
                        artifactProgress(artifact)
                    }
                }

                Text("Keep PaceBack open. There is no background-download claim; cancelling or an interruption never activates a partial model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Cancel safely", systemImage: "pause.circle", role: .cancel) {
                    store.cancelModelPackInstall()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("modelSetup.cancel")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func artifactProgress(_ artifact: ModelPackArtifactProgress) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(
                    artifact.name,
                    systemImage: artifact.state == .verified ? "checkmark.circle.fill" : "circle.dashed"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(artifact.state == .verified ? PaceBackDesign.accent : .primary)
                Spacer()
                Text(artifact.state == .verified ? "Verified" : percentText(artifact.fractionCompleted))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: artifact.fractionCompleted)
                .tint(artifact.state == .verified ? PaceBackDesign.accent : PaceBackDesign.warm)
                .accessibilityLabel(artifact.name)
                .accessibilityValue(
                    artifact.state == .verified
                        ? "Verified"
                        : "\(percentText(artifact.fractionCompleted)), \(artifact.receivedBytes) of \(artifact.expectedBytes) bytes"
                )
        }
    }

    private func verificationProgress(completed: Int, total: Int) -> some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Verifying before activation", systemImage: "checkmark.shield.fill")
                    .font(.title2.bold())
                Text("PaceBack is checking the signed manifest, exact byte counts, and SHA-256 digest for every weight and tokenizer file.")
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(completed), total: Double(total)) {
                    Text("Integrity checks")
                } currentValueLabel: {
                    Text("\(completed) of \(total) artifacts")
                }
                .tint(PaceBackDesign.accent)
                .accessibilityLabel("Integrity verification")
                .accessibilityValue("\(completed) of \(total) artifacts verified")
                Text("The staged pack becomes active only after every check succeeds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func readyPanel(_ receipt: ModelPackReceipt) -> some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 15) {
                Label("Private AI is ready offline", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .foregroundStyle(PaceBackDesign.accent)
                Text("\(receipt.installedBytes.formatted()) verified bytes are protected on this device. Questions now use local search and reranking with source citations.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatusPill(text: "Integrity checked", kind: .local)
                    StatusPill(text: "No cloud fallback", kind: .informational)
                }
                if !isRequired {
                    HStack {
                        Button("Reinstall", systemImage: "arrow.clockwise") {
                            confirmation = .reinstall
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Delete models", systemImage: "trash", role: .destructive) {
                            confirmation = .delete
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    private func failurePanel(_ failure: ModelPackFailure) -> some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 15) {
                Label("Setup stopped safely", systemImage: "exclamationmark.shield.fill")
                    .font(.title2.bold())
                    .foregroundStyle(PaceBackDesign.warm)
                Text(failure.localizedDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No partial pack was activated. Check free space or your connection, then retry. A previously verified pack is not deleted during a failed reinstall.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await store.installModelPack(
                            networkPolicy: networkPolicy,
                            force: shouldRestartCleanly(after: failure)
                        )
                    }
                } label: {
                    Label("Retry safely", systemImage: "arrow.clockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.modelPackCapacity?.hasEnoughSpace == false)
                .accessibilityIdentifier("modelSetup.retry")
            }
        }
    }

    private var whatThisUnlocks: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("What this unlocks", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                benefit("Age-matched evidence retrieval", "Filters sources before search for the active age experience.")
                benefit("Hybrid search and reranking", "Finds relevant passages, then locally orders the strongest matches.")
                benefit("Locatable source citations", "Answers must remain grounded or PaceBack abstains.")
            }
        }
    }

    private var modelExplanation: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                explanation(
                    "Weights",
                    "Frozen numeric parameters that compare meaning and rank evidence passages. PaceBack never trains or changes them."
                )
                explanation(
                    "Tokenizers",
                    "Fixed dictionaries that split questions and source text into model-readable pieces. They are not health records."
                )
                Text("The four artifacts come from two immutable Hugging Face revisions. PaceBack accepts only HTTPS, approved Hugging Face hosts, the signed manifest, exact sizes, and pinned SHA-256 values.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        } label: {
            Label("What are weights and tokenizers?", systemImage: "info.circle")
                .font(.headline)
        }
        .padding(18)
        .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius))
    }

    private var privacyReceipt: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 11) {
                Label("Privacy receipt", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(PaceBackDesign.accent)
                Text("Model bytes come in. Profile data never goes out.")
                    .font(.title3.weight(.semibold))
                privacyLine("Four fixed artifact requests; no profile ID, alias, age band, symptom, question, or care-plan field")
                privacyLine("Ephemeral requests with no cookies, cache, analytics, or cloud AI")
                privacyLine("Frozen models only—never training, fine-tuning, or learning from user or child data")
            }
        }
    }

    private var safetyBoundary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Evidence support, not medical authority")
                .font(.headline)
            Text("Local AI can retrieve and summarize cited evidence. It does not diagnose, treat, predict recovery, prescribe activity, change a clinician plan, or grant school, work, driving, or sports clearance.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let profile = store.selectedProfile {
                NavigationLink {
                    DangerSignsView(ageBand: profile.ageBand)
                } label: {
                    Label("Check urgent danger signs without AI", systemImage: "cross.case.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 4)
    }

    private func capacityRow(_ capacity: ModelPackCapacity) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(capacity.hasEnoughSpace ? "Enough free working space" : "More free space needed")
                    .font(.subheadline.weight(.semibold))
                Text(
                    "\(byteText(capacity.availableBytes)) available · \(byteText(capacity.requiredBytes)) required during staging"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: capacity.hasEnoughSpace ? "checkmark.circle.fill" : "externaldrive.badge.exclamationmark")
                .foregroundStyle(capacity.hasEnoughSpace ? PaceBackDesign.accent : PaceBackDesign.warm)
        }
        .accessibilityElement(children: .combine)
    }

    private func stage(
        _ number: String,
        _ title: String,
        symbol: String,
        state: SetupStageState
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: state == .complete ? "checkmark.circle.fill" : symbol)
                .font(.title3)
                .foregroundStyle(stageColor(state))
            Text(number)
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func stageConnector(completed: Bool) -> some View {
        Capsule()
            .fill(completed ? PaceBackDesign.accent : Color.secondary.opacity(0.22))
            .frame(height: 3)
            .padding(.top, 10)
            .accessibilityHidden(true)
    }

    private func benefit(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PaceBackDesign.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func explanation(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func privacyLine(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.primary)
            .labelStyle(ModelPrivacyLabelStyle())
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func percentText(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private func shouldRestartCleanly(after failure: ModelPackFailure) -> Bool {
        switch failure {
        case .hashMismatch, .sizeMismatch, .corruptInstallation, .invalidManifestSignature, .unexpectedManifest:
            true
        default:
            false
        }
    }

    private var downloadStageState: SetupStageState {
        switch store.modelPackStatus {
        case .notInstalled, .checking, .preparing:
            .upcoming
        case .downloading, .paused, .failed:
            .current
        case .verifying, .ready:
            .complete
        }
    }

    private var verifyStageState: SetupStageState {
        switch store.modelPackStatus {
        case .verifying:
            .current
        case .ready:
            .complete
        default:
            .upcoming
        }
    }

    private var readyStageState: SetupStageState {
        store.modelPackStatus.isReady ? .complete : .upcoming
    }

    private var stageAccessibilityLabel: String {
        switch store.modelPackStatus {
        case .downloading:
            "Setup stages: Download in progress, Verify next, Ready offline last"
        case .verifying:
            "Setup stages: Download complete, Verify in progress, Ready offline next"
        case .ready:
            "Setup stages complete: Download, Verify, Ready offline"
        default:
            "Setup stages: Download, Verify, Ready offline"
        }
    }

    private func stageColor(_ state: SetupStageState) -> Color {
        switch state {
        case .upcoming: .secondary.opacity(0.55)
        case .current: PaceBackDesign.warm
        case .complete: PaceBackDesign.accent
        }
    }
}

private enum SetupStageState: Equatable {
    case upcoming
    case current
    case complete
}

private struct ModelPrivacyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 9) {
            configuration.icon
                .foregroundStyle(PaceBackDesign.accent)
            configuration.title
        }
    }
}

#Preview("Required model setup") {
    ModelSetupView(store: PreviewFixtures.store(), isRequired: true)
}

import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.openSettings) private var openSettings
    let store: AppStore
    let profile: LocalProfile

    @State private var health: EngineHealth?
    @State private var healthError: String?

    var body: some View {
        ContentScaffold(
            "About PaceBack",
            subtitle: "An all-ages, local-first research prototype built for Hack for Humanity.",
            eyebrow: "SYSTEM MANIFEST · EVIDENCE FOUNDATION",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile, evidenceFiltered: true)
            SafetyBoundaryNotice()
            engineAndExperience
            LocalAIPipelineView()
            evidenceFoundation
            accessibilityPanel

            HStack {
                PaceBackMark(size: 28)
                Text("PaceBack 0.1 · Research prototype · Not clinically validated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
        .task { await checkHealth() }
    }

    private var engineAndExperience: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                enginePanel
                experiencePanel
            }
            VStack(alignment: .leading, spacing: 16) {
                enginePanel
                experiencePanel
            }
        }
    }

    private var enginePanel: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Local evidence engine", systemImage: "server.rack")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("ON DEVICE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(PaceBackDesign.accent)
                }

                if let health {
                    StatusBadge(
                        health.status,
                        kind: health.databaseReady && health.fts5Ready && !health.networkToolsEnabled ? .safe : .caution
                    )
                    EngineFact(label: "Engine version", value: health.version)
                    EngineFact(label: "Encrypted database", value: health.databaseReady ? "Ready" : "Unavailable")
                    EngineFact(label: "Sparse index", value: health.fts5Ready ? "FTS5 ready" : "Unavailable")
                    EngineFact(label: "Network tools", value: health.networkToolsEnabled ? "Enabled" : "Disabled")
                        .foregroundStyle(health.networkToolsEnabled ? PaceBackDesign.critical : .primary)
                } else if let healthError {
                    StatusBadge("Engine unavailable", kind: .caution)
                    Text(healthError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Check again") {
                        Task { await checkHealth() }
                    }
                    .paceBackControlTarget()
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        ProgressView("Checking signed local engine…")
                            .controlSize(.small)
                        Text("No answer path opens until the local checks succeed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var experiencePanel: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("Current experience", systemImage: "person.text.rectangle")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                EngineFact(label: "Age experience", value: profile.ageBand.title)
                EngineFact(label: "Active role", value: profile.actingRole.title)
                EngineFact(label: "Care context", value: profile.careContext.title)
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("PERMITTED EVIDENCE SCOPES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text("allAges + \(profile.ageBand.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(PaceBackDesign.accent)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var evidenceFoundation: some View {
        PaceBackCard(padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidence foundation")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Approved sources are versioned and treated as evidence—not AI instructions.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge("Source-limited", kind: .safe)
                }

                EvidenceLinkRow(
                    organization: "CDC HEADS UP",
                    title: "Returning to School",
                    destination: URL(string: "https://www.cdc.gov/heads-up/guidelines/returning-to-school.html")!
                )
                Divider().padding(.leading, 38)
                EvidenceLinkRow(
                    organization: "CDC",
                    title: "Concussion Danger Signs",
                    destination: URL(string: "https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html")!
                )
                Divider().padding(.leading, 38)
                EvidenceLinkRow(
                    organization: "CDC",
                    title: "Returning to Work Instructions",
                    destination: URL(string: "https://www.cdc.gov/traumatic-brain-injury/media/pdfs/2024/05/return_to_work_instructions_ENG-508.pdf")!
                )
                Divider().padding(.leading, 38)
                EvidenceLinkRow(
                    organization: "BJSM",
                    title: "Amsterdam 2022 Concussion Consensus",
                    destination: URL(string: "https://bjsm.bmj.com/content/57/11/695")!
                )

                PaceBackNotice(
                    "Opening a source is a user-initiated action in your default browser. PaceBack does not attach profile data to the link.",
                    style: .local
                )
            }
        }
    }

    private var accessibilityPanel: some View {
        PaceBackCard(style: .quiet) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) { accessibilityContent }
                VStack(alignment: .leading, spacing: 14) { accessibilityContent }
            }
        }
    }

    @ViewBuilder
    private var accessibilityContent: some View {
        Image(systemName: "accessibility")
            .font(.system(size: 32))
            .foregroundStyle(PaceBackDesign.accent)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
            Text("Make the workspace easier to read")
                .font(.title3.weight(.semibold))
            Text("Adjust text and control scale, spacing, reading detail, answer narration, and motion. PaceBack also responds to macOS Reduce Motion, Reduce Transparency, and Increase Contrast.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 10)
        Button {
            openSettings()
        } label: {
            Label("Open Settings", systemImage: "gearshape")
        }
        .buttonStyle(.borderedProminent)
        .paceBackControlTarget()
        .keyboardShortcut(",", modifiers: .command)
    }

    private func checkHealth() async {
        health = nil
        healthError = nil
        do {
            health = try await store.aiEngine.health()
        } catch is CancellationError {
            return
        } catch {
            healthError = error.localizedDescription
        }
    }
}

private struct EngineFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospaced().weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LocalAIPipelineView: View {
    private let steps = [
        ("01", "Retrieve", "BM25 + BGE"),
        ("02", "Fuse", "RRF k=60"),
        ("03", "Rerank", "Local MiniLM"),
        ("04", "Budget", "Protected facts"),
        ("05", "Verify", "Cite or abstain")
    ]

    var body: some View {
        PaceBackCard(padding: 22) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The local AI path")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Hybrid retrieval and bounded orchestration, aligned to the recovery-support problem.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge("Frozen generator", kind: .informational)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { pipelineSteps }
                    VStack(alignment: .leading, spacing: 12) { pipelineSteps }
                }

                PaceBackNotice(
                    "The pipeline can retrieve at most three rounds and must stop or abstain at its hard action limits.",
                    style: .boundary
                )
            }
        }
    }

    @ViewBuilder
    private var pipelineSteps: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            VStack(alignment: .leading, spacing: 4) {
                Text(step.0)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(index == 0 ? PaceBackDesign.warm : PaceBackDesign.accent)
                Text(step.1).font(.callout.weight(.semibold))
                Text(step.2).font(.caption.monospaced()).foregroundStyle(.secondary)
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

private struct EvidenceLinkRow: View {
    let organization: String
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 13) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(PaceBackDesign.accent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(organization)
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.callout.weight(.semibold))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .paceBackControlTarget()
        .accessibilityHint("Opens the source in the default browser without profile data")
    }
}

public struct PaceBackSettingsView: View {
    let store: AppStore
    @State private var administrativeGateUnlocked = false

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let profile = store.selectedProfile {
                if !RolePolicy.permits(.changeSettings, profile: profile) {
                    lockedSettings(
                        title: profile.ageBand.isPediatric ? "Guardian settings" : "Profile-owner settings",
                        message: profile.ageBand.isPediatric
                            ? "This profile’s current role cannot change app settings. Switch to guardian mode in Privacy."
                            : "Approved caregivers cannot change app settings. Return to profile-owner mode in Privacy using Mac authentication."
                    )
                } else if RolePolicy.requiresAdministrativeGate(.changeSettings, profile: profile),
                          !administrativeGateUnlocked {
                    lockedSettings(
                        title: "Parent or guardian approval",
                        message: "Unlock these settings with this Mac’s device-owner authentication."
                    )
                } else {
                    settingsForm
                }
            } else {
                ContentUnavailableView("No profile", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .paceBackTextScale(store.preferences.textScale)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 520)
    }

    @ViewBuilder
    private var settingsForm: some View {
        @Bindable var preferences = store.preferences
        TabView {
            Form {
                Section("Reading experience") {
                    Picker("Reading detail", selection: $preferences.readingMode) {
                        ForEach(ReadingMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Slider(value: $preferences.textScale, in: 0.9...1.5, step: 0.1) {
                        Text("Text and control scale")
                    } minimumValueLabel: {
                        Text("A")
                    } maximumValueLabel: {
                        Text("A").font(.title2)
                    }
                    .accessibilityValue("\(preferences.textScale.formatted(.number.precision(.fractionLength(1)))) times")
                    Text("Current scale: \(preferences.textScale.formatted(.number.precision(.fractionLength(1))))×")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Toggle("Use comfortable spacing", isOn: $preferences.comfortableSpacing)
                        .paceBackControlTarget()
                    Toggle("Read evidence answers aloud", isOn: $preferences.readAnswersAloud)
                        .paceBackControlTarget()
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Reading", systemImage: "textformat.size") }

            Form {
                Section("Motion and contrast") {
                    Toggle("Always reduce app motion", isOn: $preferences.reduceMotionOverride)
                        .paceBackControlTarget()
                    Text("PaceBack also responds to macOS Reduce Motion, Reduce Transparency, and Increase Contrast settings.")
                        .foregroundStyle(.secondary)
                    Label("Status uses text and an icon—not color alone.", systemImage: "checkmark.circle")
                }
                Section("Keyboard and assistive technology") {
                    Label("Native controls support keyboard focus and VoiceOver semantics.", systemImage: "keyboard")
                    Label("Evidence passages and technical locators support text selection.", systemImage: "text.cursor")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Accessibility", systemImage: "accessibility") }
        }
        .scenePadding()
    }

    private func lockedSettings(title: String, message: String) -> some View {
        ZStack {
            PaceBackCanvasBackground()
            VStack(spacing: 16) {
                PaceBackMark(size: 54)
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundStyle(PaceBackDesign.accent)
                Text(title).font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 390)
                if let profile = store.selectedProfile,
                   RolePolicy.permits(.changeSettings, profile: profile) {
                    Button("Unlock settings") {
                        Task {
                            administrativeGateUnlocked = await store.authorize(.changeSettings)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .paceBackControlTarget()
                }
            }
            .padding(40)
        }
    }
}

public struct PaceBackCommands: Commands {
    private let store: AppStore

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some Commands {
        SidebarCommands()
        CommandMenu("PaceBack") {
            Button("Today") { store.selectedSection = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("Focus Session") { store.selectedSection = .focus }
                .keyboardShortcut("2", modifiers: .command)
            Button("Simplify") { store.selectedSection = .simplify }
                .keyboardShortcut("3", modifiers: .command)
            Button("Ask Evidence") { store.selectedSection = .askEvidence }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
            Button("Check Danger Signs") { store.presentedSheet = .dangerSigns }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}

import SwiftUI

public struct PaceBackRootView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private let store: AppStore
    private let sidecarState: SidecarRuntimeState

    public init(store: AppStore, sidecarState: SidecarRuntimeState = .idle) {
        self.store = store
        self.sidecarState = sidecarState
    }

    public var body: some View {
        Group {
            if !store.hasLoaded || store.isLoading {
                PaceBackLaunchView()
            } else if store.needsOnboarding {
                OnboardingView(store: store)
            } else {
                AppNavigationView(
                    store: store,
                    evidenceEngineConnected: {
                        if case .connected = sidecarState { return true }
                        return false
                    }()
                )
            }
        }
        .tint(PaceBackDesign.accent)
        .paceBackTextScale(store.preferences.textScale)
        .transaction { transaction in
            if systemReduceMotion || store.preferences.reduceMotionOverride {
                transaction.disablesAnimations = true
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidecarStatusBar(state: sidecarState)
        }
        .task { await store.load() }
        .alert(
            "PaceBack could not complete that action",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            ),
            presenting: store.lastError
        ) { _ in
            Button("OK") { store.lastError = nil }
        } message: { message in
            Text(message)
        }
    }
}

private struct PaceBackLaunchView: View {
    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            VStack(spacing: 18) {
                PaceBackMark(size: 68)
                VStack(spacing: 5) {
                    Text("PaceBack")
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Opening your private recovery workspace")
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Opening encrypted local profiles")
                Label("Encrypted profiles stay on this Mac", systemImage: "lock.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PaceBackDesign.accent)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

private struct SidecarStatusBar: View {
    let state: SidecarRuntimeState

    var body: some View {
        HStack(spacing: 10) {
            Label("LOCAL", systemImage: icon)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(foregroundStyle)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 1, height: 14)
                .accessibilityHidden(true)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text("No cloud generation")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Local evidence engine status. \(message). No cloud generation.")
    }

    private var message: String {
        switch state {
        case .idle, .starting:
            "Starting the private evidence engine…"
        case .connected:
            "Evidence engine connected · profile data stays on device"
        case .unavailable(let reason):
            "Evidence engine unavailable · no answer will be simulated. \(reason)"
        case .stopped:
            "Evidence engine stopped"
        }
    }

    private var icon: String {
        switch state {
        case .connected: "checkmark.shield.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .idle, .starting: "hourglass"
        case .stopped: "stop.circle.fill"
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .connected: PaceBackDesign.accent
        case .unavailable: PaceBackDesign.warm
        case .idle, .starting, .stopped: .secondary
        }
    }
}

private struct AppNavigationView: View {
    @Bindable var store: AppStore
    let evidenceEngineConnected: Bool

    private let dailySections: [AppSection] = [.today, .focus]
    private let evidenceSections: [AppSection] = [.simplify, .askEvidence, .trends]
    private let planSections: [AppSection] = [.carePlan, .privacy]

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarBrand
                profilePicker
                Divider().padding(.horizontal, 14)
                navigationList
                sidebarFooter
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
            .navigationSplitViewColumnWidth(
                min: 224,
                ideal: PaceBackDesign.sidebarWidth,
                max: 300
            )
        } detail: {
            if let profile = store.selectedProfile {
                detail(for: store.selectedSection, profile: profile)
            } else {
                ZStack {
                    PaceBackCanvasBackground()
                    ContentUnavailableView(
                        "No profile selected",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Add a private local profile to continue.")
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.presentedSheet = .dangerSigns
                } label: {
                    Label("Check danger signs", systemImage: "cross.case.fill")
                }
                .help("Open the deterministic emergency safety check")
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .accessibilityHint("This safety check does not use AI")
            }
        }
        .sheet(item: $store.presentedSheet) { sheet in
            switch sheet {
            case .dangerSigns:
                if let profile = store.selectedProfile {
                    DangerSignsView(ageBand: profile.ageBand)
                }
            case .addProfile:
                AddProfileView(store: store)
            }
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            PaceBackMark(size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("PaceBack")
                    .font(.title3.weight(.bold))
                Text("Recovery field guide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVE LOCAL PROFILE")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Picker(
                "Active local profile",
                selection: Binding(
                    get: { store.selectedProfileID },
                    set: { id in
                        if let id { store.selectProfile(id) }
                    }
                )
            ) {
                ForEach(store.profiles) { profile in
                    Text("\(profile.alias) · \(profile.ageBand.shortTitle)")
                        .tag(Optional(profile.id))
                }
            }
            .labelsHidden()
            .accessibilityLabel("Active local profile")

            if let profile = store.selectedProfile {
                HStack(spacing: 8) {
                    Text(profile.ageBand.shortTitle)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(PaceBackDesign.calmBlue.opacity(0.11), in: Capsule())
                    Text(profile.actingRole.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(PaceBackDesign.accent)
                        .accessibilityLabel("Encrypted profile")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var navigationList: some View {
        List(selection: $store.selectedSection) {
            navigationSection("TODAY", sections: dailySections)
            navigationSection("UNDERSTAND", sections: evidenceSections)
            navigationSection("PLAN & TRUST", sections: planSections)
            Section {
                navigationRow(.about)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func navigationSection(_ title: String, sections: [AppSection]) -> some View {
        Section {
            ForEach(sections) { section in
                navigationRow(section)
            }
        } header: {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
        }
    }

    private func navigationRow(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .font(.body.weight(store.selectedSection == section ? .semibold : .regular))
            .padding(.vertical, 4)
            .tag(section)
            .accessibilityLabel(section.title)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityHidden(true)
                Text("Private by design")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .accessibilityElement(children: .combine)

            Button {
                store.presentedSheet = .addProfile
            } label: {
                Label("Add local profile", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .paceBackControlTarget()
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func detail(for section: AppSection, profile: LocalProfile) -> some View {
        switch section {
        case .today: TodayView(store: store, profile: profile)
        case .focus: FocusSessionView(store: store, profile: profile)
        case .simplify: SimplifyView(store: store, profile: profile)
        case .askEvidence:
            AskEvidenceView(
                store: store,
                profile: profile,
                engineConnected: evidenceEngineConnected
            )
        case .trends: TrendsView(store: store, profile: profile)
        case .carePlan: CarePlanView(store: store, profile: profile)
        case .privacy: PrivacyView(store: store, profile: profile)
        case .about: AboutSettingsView(store: store, profile: profile)
        }
    }
}

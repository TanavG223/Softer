import SwiftUI

public struct PaceBackRootView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private let store: AppStore

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if !store.hasLoaded || store.isLoading {
                PaceBackLaunchView()
            } else if store.isGuestSession {
                AppNavigationView(store: store)
            } else if let workspaceError = store.workspaceErrorMessage {
                EncryptedWorkspaceUnavailableView(store: store, message: workspaceError)
            } else if store.needsOnboarding {
                OnboardingView(store: store)
            } else {
                AppNavigationView(store: store)
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
            PersistentSupportBar(store: store)
        }
        .task { await store.load() }
        .sheet(
            item: Binding(
                get: { store.presentedSheet },
                set: { store.presentedSheet = $0 }
            )
        ) { sheet in
            switch sheet {
            case .support:
                NavigationStack {
                    SupportHubView(
                        store: store,
                        ageBand: store.selectedProfile?.ageBand,
                        showsDoneButton: true
                    )
                }
                .frame(minWidth: 700, minHeight: 650)
            case .addProfile:
                AddProfileView(store: store)
            }
        }
        .alert(
            "Softer could not complete that action",
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

private struct EncryptedWorkspaceUnavailableView: View {
    let store: AppStore
    let message: String
    @State private var guestAgeBand: AgeBand = .adult18To64

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            VStack(spacing: 18) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 50))
                    .foregroundStyle(PaceBackDesign.warm)
                    .accessibilityHidden(true)
                Text("Encrypted workspace unavailable")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .textSelection(.enabled)
                Text("Softer has not treated the workspace as empty or written new profile data.")
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                GuestSessionControls(store: store, ageBand: $guestAgeBand)
                    .frame(maxWidth: 560)

                HStack(spacing: 12) {
                    Button {
                        Task { await store.retryWorkspaceLoad() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        store.presentedSheet = .support
                    } label: {
                        Label("Open Support", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Text("Guest activity choices and check-outs stay only in memory and disappear when you leave Softer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            .padding(44)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

private struct PaceBackLaunchView: View {
    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            VStack(spacing: 18) {
                PaceBackMark(size: 68)
                VStack(spacing: 5) {
                    Text("Softer")
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Opening your private wellbeing space")
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Opening encrypted local profiles")
                Label("No account, ads, or passive mood tracking", systemImage: "lock.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PaceBackDesign.accent)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

private struct PersistentSupportBar: View {
    let store: AppStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var content: some View {
        PersistentSupportButton(store: store)
        Text("Urgent support is static and works without a profile.")
            .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Label(
            store.isGuestSession ? "Guest session · nothing saved" : "Private local profiles",
            systemImage: store.isGuestSession ? "eye.slash.fill" : "lock.fill"
        )
            .foregroundStyle(PaceBackDesign.accent)
            .accessibilityElement(children: .combine)
    }
}

private struct AppNavigationView: View {
    @Bindable var store: AppStore

    private let calmSections: [AppSection] = [.calm]
    private let toolkitSections: [AppSection] = [.toolkit, .play]
    private let youSections: [AppSection] = [.support, .privacy, .about]

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
                max: 310
            )
        } detail: {
            if let profile = store.selectedProfile {
                NavigationStack {
                    detail(for: store.selectedSection, profile: profile)
                        .navigationDestination(for: WellbeingLaunch.self) { launch in
                            WellbeingSessionHostView(
                                store: store,
                                profile: profile,
                                launch: launch
                            )
                        }
                }
                .id(profile.id)
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
                PersistentSupportButton(store: store, compact: true)
            }
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            PaceBackMark(size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Softer")
                    .font(.title3.weight(.bold))
                Text("Small choices for stressful moments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            Text(store.isGuestSession ? "TEMPORARY GUEST" : "ACTIVE LOCAL PROFILE")
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
                    Image(systemName: store.isGuestSession ? "eye.slash.fill" : "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(PaceBackDesign.accent)
                        .accessibilityLabel(store.isGuestSession ? "Temporary guest session" : "Encrypted profile")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var navigationList: some View {
        List(selection: $store.selectedSection) {
            navigationSection("CALM", sections: calmSections)
            navigationSection("TOOLKIT", sections: toolkitSections)
            navigationSection("YOU", sections: youSections)
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
                Image(systemName: "lock.shield")
                    .foregroundStyle(PaceBackDesign.accent)
                    .accessibilityHidden(true)
                Text("No passive mental-state inference")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .accessibilityElement(children: .combine)

            if store.isGuestSession {
                Button {
                    Task { await store.returnToEncryptedWorkspace() }
                } label: {
                    Label("Return to encrypted profiles", systemImage: "lock.rotation")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .paceBackControlTarget()
                .accessibilityHint("Ends this guest session and discards its temporary choices")
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func detail(for section: AppSection, profile: LocalProfile) -> some View {
        switch section {
        case .calm:
            CalmHomeView(store: store, profile: profile)
        case .toolkit:
            WellbeingToolkitView(store: store, profile: profile)
        case .play:
            WellbeingPlayView(store: store, profile: profile)
        case .support:
            SupportHubView(store: store, ageBand: profile.ageBand)
        case .privacy:
            WellbeingPrivacyView(store: store, profile: profile)
        case .about:
            WellbeingAboutView(store: store, profile: profile)
        }
    }
}

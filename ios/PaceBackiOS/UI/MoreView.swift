import SwiftUI

private enum MoreSheet: String, Identifiable {
    case addProfile

    var id: String { rawValue }
}

private enum MoreConfirmation: String, Identifiable {
    case deleteProfile

    var id: String { rawValue }
}

struct MoreView: View {
    let store: AppStore
    @State private var sheet: MoreSheet?
    @State private var confirmation: MoreConfirmation?

    private var profile: LocalProfile { store.selectedProfile! }

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        "Private by architecture",
                        detail: "Profiles, roles, reading preferences, privacy boundaries, and prototype status are visible here."
                    )
                    profileCard
                    readingCard
                    modelCard
                    privacyCard
                    aboutCard
                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .addProfile:
                AddProfileView(store: store)
            }
        }
        .alert(item: $confirmation) { item in
            switch item {
            case .deleteProfile:
                Alert(
                    title: Text("Delete \(profile.alias)?"),
                    message: Text("This permanently removes the encrypted local profile from this device."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task { _ = await store.deleteSelectedProfile() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var profileCard: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    PaceBackMark(size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.alias)
                            .font(.title3.bold())
                        Text("Alias only · created on this device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ProfileStrip(profile: profile)
                accessControls

                if store.profiles.count > 1 {
                    Picker("Active profile", selection: Binding(
                        get: { profile.id },
                        set: { store.selectProfile($0) }
                    )) {
                        ForEach(store.profiles) { item in
                            Text("\(item.alias) · \(item.ageBand.compactTitle)").tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .paceBackControlTarget()
                }

                HStack {
                    Button("Add profile", systemImage: "person.badge.plus") {
                        sheet = .addProfile
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        confirmation = .deleteProfile
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Text("Pediatric creation and protected pediatric actions require device authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var accessControls: some View {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
            Text("Role handoff")
                .font(.headline)

            switch profile.ageBand {
            case .youngChild0To5, .child6To12:
                let target: ActingRole = profile.actingRole == .guardian ? .caregiver : .guardian
                Button("Switch to \(target.title)", systemImage: "person.2.badge.gearshape") {
                    Task { _ = await store.switchRole(to: target) }
                }
                .buttonStyle(.bordered)
                Text("Changing who administers an under-13 profile requires device authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .teen13To17:
                let target: ActingRole = profile.actingRole == .guardian ? .teenUser : .guardian
                Button(
                    profile.actingRole == .guardian ? "Hand session to teen" : "Enter guardian controls",
                    systemImage: profile.actingRole == .guardian ? "person.crop.circle.badge.checkmark" : "lock.shield"
                ) {
                    Task { _ = await store.switchRole(to: target) }
                }
                .buttonStyle(.bordered)
                Text("Entering guardian controls requires device authentication; handing the guided session back does not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .adult18To64, .olderAdult65Plus:
                if profile.actingRole == .selfManaged {
                    if profile.caregiverApproved {
                        StatusPill(text: "Caregiver access approved", kind: .local)
                        HStack {
                            Button("Hand to caregiver", systemImage: "person.2") {
                                Task { _ = await store.switchRole(to: .caregiver) }
                            }
                            .buttonStyle(.bordered)
                            Button("Revoke", role: .destructive) {
                                Task { _ = await store.setCaregiverApproval(false) }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button("Approve caregiver access", systemImage: "person.badge.key") {
                            Task { _ = await store.setCaregiverApproval(true) }
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Approval is local, explicit, and revocable by the profile owner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Return to owner controls", systemImage: "lock.shield") {
                        Task { _ = await store.switchRole(to: .selfManaged) }
                    }
                    .buttonStyle(.bordered)
                    Text("Returning from caregiver mode requires device authentication.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var readingCard: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Reading detail", systemImage: "textformat.size")
                    .font(.headline)
                Picker("Reading detail", selection: Binding(
                    get: { store.readingMode },
                    set: { store.readingMode = $0 }
                )) {
                    ForEach(ReadingMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("System Dynamic Type, VoiceOver, Increase Contrast, and Reduce Transparency settings remain in control of presentation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyCard: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Privacy receipt", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(PaceBackDesign.accent)
                privacyRow("No account, ads, trackers, telemetry, or push notifications")
                privacyRow("One AES-GCM key per profile in the iOS Keychain")
                privacyRow("Encrypted profile files use iOS Data Protection")
                privacyRow("No health question leaves the device")
                privacyRow("No external LLM or web search fallback")
            }
        }
    }

    private var modelCard: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Private AI model", systemImage: "cpu.fill")
                        .font(.headline)
                    Spacer()
                    StatusPill(
                        text: store.modelPackStatus.isReady ? "Ready offline" : "Setup needed",
                        kind: store.modelPackStatus.isReady ? .local : .informational
                    )
                }
                Text("Inspect the signed model receipt, verify again, delete local weights, or reinstall without touching profile data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    ModelSetupView(store: store, isRequired: false)
                } label: {
                    Label("Open model setup", systemImage: "chevron.forward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var aboutCard: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PaceBack for iOS")
                        .font(.headline)
                    Spacer()
                    StatusPill(text: "0.1 research", kind: .informational)
                }
                Text("Native SwiftUI companion · iOS 18+")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Verified local BGE and MiniLM models power private evidence retrieval after setup. PaceBack remains an unvalidated research prototype and abstains when its local model, corpus, or citation checks are unavailable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func privacyRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .labelStyle(PrivacyLabelStyle())
    }
}

private struct PrivacyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .foregroundStyle(PaceBackDesign.accent)
            configuration.title
        }
    }
}

private struct AddProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore

    @State private var alias = ""
    @State private var ageBand: AgeBand = .adult18To64
    @State private var actingRole: ActingRole = .selfManaged
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Private profile") {
                    TextField("Alias, not a legal name", text: $alias)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: alias) { _, value in
                            if value.count > 40 { alias = String(value.prefix(40)) }
                        }
                    Picker("Age group", selection: $ageBand) {
                        ForEach(AgeBand.allCases) { band in
                            Text(band.title).tag(band)
                        }
                    }
                    .onChange(of: ageBand) { _, newBand in
                        actingRole = RolePolicy.creationRoles(for: newBand)[0]
                    }
                    Picker("Active role", selection: $actingRole) {
                        ForEach(RolePolicy.creationRoles(for: ageBand)) { role in
                            Text(role.title).tag(role)
                        }
                    }
                }
                Section {
                    Text(ageBand.experienceSummary)
                    if ageBand.isPediatric {
                        Label("Device authentication required", systemImage: "faceid")
                            .foregroundStyle(PaceBackDesign.accent)
                    }
                }
                Section {
                    Button {
                        isCreating = true
                        Task {
                            let created = await store.createProfile(
                                alias: alias,
                                ageBand: ageBand,
                                actingRole: actingRole
                            )
                            isCreating = false
                            if created { dismiss() }
                        }
                    } label: {
                        if isCreating {
                            ProgressView("Creating encrypted profile…")
                        } else {
                            Label("Create encrypted profile", systemImage: "lock.shield.fill")
                        }
                    }
                    .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .navigationTitle("Add profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MoreView(store: PreviewFixtures.store(profile: PreviewFixtures.child))
    }
}

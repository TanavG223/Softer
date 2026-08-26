import SwiftUI

struct OnboardingView: View {
    let store: AppStore

    @State private var alias = ""
    @State private var ageBand: AgeBand = .adult18To64
    @State private var actingRole: ActingRole = .selfManaged
    @State private var acknowledged = false
    @State private var isCreating = false
    @FocusState private var aliasFocused: Bool

    private var availableRoles: [ActingRole] {
        RolePolicy.creationRoles(for: ageBand)
    }

    private var canCreate: Bool {
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && acknowledged && !isCreating
    }

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brandHeader
                    hero
                    ageRail
                    profileForm
                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            PaceBackMark(size: 50)
            VStack(alignment: .leading, spacing: 1) {
                Text("PaceBack")
                    .font(.title2.bold())
                Text("LOCAL · ALL AGES · CARE-LED")
                    .font(.caption2.bold())
                    .tracking(0.9)
                    .foregroundStyle(PaceBackDesign.accent)
            }
            Spacer()
            StatusPill(text: "Prototype", kind: .informational)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A steadier way back to everyday life.")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Keep a recovery workspace private, check urgent danger signs without AI, and follow the plan you made with a clinician.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ageRail: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("FIVE AGE-SAFE EXPERIENCES")
                    .font(.caption2.bold())
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(AgeBand.allCases) { band in
                        VStack(spacing: 7) {
                            Circle()
                                .fill(band == ageBand ? PaceBackDesign.warm : PaceBackDesign.accent)
                                .frame(width: 9, height: 9)
                            Text(band.compactTitle)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(band.title)
                    }
                }
                Text("Caregiver-led for young children · guided for children and teens · self-managed or explicitly shared for adults")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var profileForm: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create a private profile")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Alias and age band only. No account, legal name, or birth date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("1  Choose an alias", systemImage: "person.crop.circle")
                        .font(.headline)
                    TextField("Alias, not a legal name", text: $alias)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($aliasFocused)
                        .onChange(of: alias) { _, value in
                            if value.count > 40 { alias = String(value.prefix(40)) }
                        }
                        .accessibilityHint("Enter up to 40 characters")
                        .accessibilityIdentifier("onboarding.alias")
                    Text("\(alias.count)/40 characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("2  Select the age experience", systemImage: "figure.and.child.holdinghands")
                        .font(.headline)
                    Picker("Age group", selection: $ageBand) {
                        ForEach(AgeBand.allCases) { band in
                            Text(band.title).tag(band)
                        }
                    }
                    .pickerStyle(.menu)
                    .paceBackControlTarget()
                    .accessibilityIdentifier("onboarding.ageBand")
                    .onChange(of: ageBand) { _, newBand in
                        actingRole = RolePolicy.creationRoles(for: newBand)[0]
                    }
                    Text(ageBand.experienceSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("3  Set the active role", systemImage: "person.badge.key.fill")
                        .font(.headline)
                    Picker("Who is using this profile?", selection: $actingRole) {
                        ForEach(availableRoles) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .paceBackControlTarget()
                    .accessibilityIdentifier("onboarding.actingRole")
                    if ageBand.isPediatric {
                        Label(
                            "Device authentication is required to create this pediatric profile.",
                            systemImage: "lock.shield.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(PaceBackDesign.accent)
                    } else {
                        Text("Caregiver sharing can be approved and revoked later by the profile owner.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $acknowledged) {
                    Text("I understand PaceBack supports—but does not replace—professional care.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .paceBackControlTarget()
                .accessibilityIdentifier("onboarding.acknowledgement")

                Button {
                    isCreating = true
                    Task {
                        _ = await store.createProfile(
                            alias: alias,
                            ageBand: ageBand,
                            actingRole: actingRole
                        )
                        isCreating = false
                    }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView().tint(.white)
                            Text("Securing profile…")
                        } else {
                            Label("Create encrypted profile", systemImage: "lock.shield.fill")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)
                .accessibilityHint(ageBand.isPediatric ? "Requests device authentication" : "Creates the profile on this device")
                .accessibilityIdentifier("onboarding.createProfile")
            }
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(
        store: AppStore(
            repository: InMemoryProfileRepository(),
            aiEngine: OnDeviceUnavailableAIEngine(),
            guardianAuthenticator: AllowingGuardianAuthenticator()
        )
    )
}

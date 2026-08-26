import SwiftUI

struct OnboardingView: View {
    let store: AppStore

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    brandHeader

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 44) {
                            onboardingStory
                                .frame(maxWidth: 480, alignment: .leading)
                            ProfileForm(store: store, requiresSafetyAcknowledgement: true)
                                .frame(maxWidth: 520)
                        }

                        VStack(alignment: .leading, spacing: 28) {
                            onboardingStory
                            ProfileForm(store: store, requiresSafetyAcknowledgement: true)
                        }
                    }

                    SafetyBoundaryNotice()
                }
                .frame(maxWidth: 1_100, alignment: .leading)
                .padding(48)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 840, minHeight: 680)
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            PaceBackMark(size: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("PaceBack")
                    .font(.title.weight(.bold))
                Text("PRIVATE · LOCAL · EVIDENCE-GROUNDED")
                    .font(.caption2.weight(.bold))
                    .tracking(1.15)
                    .foregroundStyle(PaceBackDesign.accent)
            }
            Spacer()
            StatusBadge("Research prototype", kind: .informational)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var onboardingStory: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text("A steadier way back to everyday life.")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Organize a clinician’s plan, pace short sessions, simplify dense documents, and ask questions against age-matched evidence—without sending health information off this Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ageContinuum
            trustRail
        }
    }

    private var ageContinuum: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ONE WORKSPACE · FIVE AGE-SAFE EXPERIENCES")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(AgeBand.allCases.enumerated()), id: \.element.id) { index, band in
                    VStack(spacing: 7) {
                        Circle()
                            .fill(index == 0 ? PaceBackDesign.warm : PaceBackDesign.accent)
                            .frame(width: 9, height: 9)
                            .overlay { Circle().stroke(.background, lineWidth: 2) }
                        Text(band.shortTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(band.title)

                    if index < AgeBand.allCases.count - 1 {
                        Rectangle()
                            .fill(PaceBackDesign.accent.opacity(0.30))
                            .frame(maxWidth: .infinity, maxHeight: 2)
                            .offset(y: -10)
                            .accessibilityHidden(true)
                    }
                }
            }
            Text("Caregiver-led for young children · guided for children and teens · self-managed or explicitly shared for adults")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trustRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingPrinciple(
                number: "01",
                icon: "lock.shield",
                title: "Local by architecture",
                detail: "No account, ads, analytics, cloud model, or profile-data transmission."
            )
            Divider().padding(.leading, 52)
            OnboardingPrinciple(
                number: "02",
                icon: "checkmark.seal",
                title: "Evidence stays visible",
                detail: "Answers show supporting passages or clearly say when information is insufficient."
            )
            Divider().padding(.leading, 52)
            OnboardingPrinciple(
                number: "03",
                icon: "hand.raised",
                title: "People keep control",
                detail: "Imported plan items remain unconfirmed until an authorized person checks the original."
            )
        }
    }
}

private struct OnboardingPrinciple: View {
    let number: String
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(PaceBackDesign.warm)
                .frame(width: 28, alignment: .leading)
            Image(systemName: icon)
                .foregroundStyle(PaceBackDesign.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

struct AddProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore

    var body: some View {
        NavigationStack {
            ZStack {
                PaceBackCanvasBackground()
                ScrollView {
                    ProfileForm(store: store, requiresSafetyAcknowledgement: false) {
                        dismiss()
                    }
                    .padding(28)
                }
            }
            .navigationTitle("Add a private local profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 640)
    }
}

private struct ProfileForm: View {
    let store: AppStore
    let requiresSafetyAcknowledgement: Bool
    var onCreated: (() -> Void)?

    @State private var alias = ""
    @State private var ageBand: AgeBand = .adult18To64
    @State private var actingRole: ActingRole = .selfManaged
    @State private var acknowledged = false
    @State private var isSaving = false
    @FocusState private var aliasFocused: Bool

    init(
        store: AppStore,
        requiresSafetyAcknowledgement: Bool,
        onCreated: (() -> Void)? = nil
    ) {
        self.store = store
        self.requiresSafetyAcknowledgement = requiresSafetyAcknowledgement
        self.onCreated = onCreated
    }

    var body: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Create your private profile")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Three choices. No account required.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(PaceBackDesign.accent)
                        .accessibilityHidden(true)
                }

                formStep(number: "1", title: "Choose an alias") {
                    VStack(alignment: .leading, spacing: 7) {
                        TextField("Alias", text: $alias)
                            .textFieldStyle(.roundedBorder)
                            .focused($aliasFocused)
                            .paceBackControlTarget()
                            .accessibilityHint("Enter up to 40 characters; avoid a legal name")
                        HStack {
                            Label("No name or birth date", systemImage: "person.crop.circle.badge.minus")
                            Spacer()
                            Text("\(min(alias.count, 40))/40")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                formStep(number: "2", title: "Select the age experience") {
                    Picker("Age group", selection: $ageBand) {
                        ForEach(AgeBand.allCases) { band in
                            Text(band.title).tag(band)
                        }
                    }
                    .pickerStyle(.menu)
                    .paceBackControlTarget()
                    .onChange(of: ageBand) { _, newValue in
                        actingRole = availableRoles(for: newValue)[0]
                    }
                }

                formStep(number: "3", title: "Set the active role") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Who is using this profile?", selection: $actingRole) {
                            ForEach(availableRoles(for: ageBand)) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        .pickerStyle(.menu)
                        .paceBackControlTarget()
                        roleExplanation
                    }
                }

                if requiresSafetyAcknowledgement {
                    Toggle(isOn: $acknowledged) {
                        Text("I understand this research prototype supports—but does not replace—professional care.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                    .paceBackControlTarget()
                }

                Button {
                    isSaving = true
                    Task {
                        let created = await store.createProfile(alias: alias, ageBand: ageBand, actingRole: actingRole)
                        isSaving = false
                        if created { onCreated?() }
                    }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().controlSize(.small)
                            Text("Creating encrypted profile…")
                        } else {
                            Label("Create encrypted profile", systemImage: "lock.shield.fill")
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .paceBackControlTarget()
                .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || alias.count > 40 ||
                    (requiresSafetyAcknowledgement && !acknowledged) || isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { aliasFocused = true }
    }

    private func formStep<Content: View>(
        number: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(PaceBackDesign.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    @ViewBuilder
    private var roleExplanation: some View {
        switch ageBand {
        case .youngChild0To5, .child6To12:
            PaceBackNotice(
                "A parent, guardian, or caregiver operates this profile. Child-facing freeform AI is disabled.",
                style: .local
            )
        case .teen13To17:
            PaceBackNotice(
                "A guardian initializes the profile. Teen mode can use guided tools; guardian mode protects plans, clipboard reports, deletion, and settings.",
                style: .local
            )
        case .adult18To64, .olderAdult65Plus:
            PaceBackNotice(
                "The profile starts self-managed. Caregiver access must be explicitly approved and can be revoked.",
                style: .local
            )
        }
    }

    private func availableRoles(for ageBand: AgeBand) -> [ActingRole] {
        switch ageBand {
        case .youngChild0To5, .child6To12: [.guardian, .caregiver]
        case .teen13To17: [.teenUser, .guardian]
        case .adult18To64, .olderAdult65Plus: [.selfManaged]
        }
    }
}

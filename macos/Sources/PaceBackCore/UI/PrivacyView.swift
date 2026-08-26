import SwiftUI

struct PrivacyView: View {
    let store: AppStore
    let profile: LocalProfile

    @State private var preferenceDraft = ""
    @State private var confirmDeletion = false
    @State private var isSwitchingRole = false

    var body: some View {
        ContentScaffold(
            "Privacy",
            subtitle: "Your recovery information stays local and separated by encrypted profile.",
            eyebrow: "LOCAL-FIRST · PROFILE ISOLATED",
            comfortableSpacing: store.preferences.comfortableSpacing
        ) {
            ProfileContextStrip(profile: profile)
            PrivacyArchitectureView(profile: profile)

            roleHandoffCard

            PaceBackCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Inspectable personalization memory")
                                .font(.title3.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("Editable external memory · model weights stay frozen")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge("\(profile.confirmedPreferences.count) saved", kind: .informational)
                    }
                    Text("Only preferences you explicitly confirm appear here. They do not change model weights or infer a condition.")
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { preferenceComposer }
                        VStack(alignment: .leading, spacing: 8) { preferenceComposer }
                    }
                    if profile.confirmedPreferences.isEmpty {
                        PaceBackNotice(
                            "No saved preferences. The app will not infer one from health activity.",
                            style: .local
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(profile.confirmedPreferences.enumerated()), id: \.element) { index, preference in
                                HStack(spacing: 12) {
                                    Label(preference, systemImage: "checkmark.circle")
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button("Remove", systemImage: "xmark") {
                                        Task { await store.removeConfirmedPreference(preference) }
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .frame(width: 44, height: 44)
                                    .help("Remove \(preference)")
                                    .accessibilityLabel("Remove preference: \(preference)")
                                }
                                if index < profile.confirmedPreferences.count - 1 {
                                    Divider().padding(.leading, 28)
                                }
                            }
                        }
                    }
                }
            }

            if !profile.ageBand.isPediatric && profile.actingRole == .selfManaged {
                PaceBackCard(style: .prominent) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Adult caregiver approval").font(.title3.weight(.semibold))
                        Text("Approval is revocable and applies only to this local profile on this Mac.")
                            .foregroundStyle(.secondary)
                        Toggle("An adult caregiver is approved", isOn: Binding(
                            get: { profile.caregiverApproved },
                            set: { approved in Task { await store.setCaregiverApproved(approved) } }
                        ))
                        .paceBackControlTarget()
                        Text("After approval, use the role-handoff control above to enter caregiver mode. Return to profile-owner mode requires Mac authentication.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PaceBackCard(style: .caution) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Delete this profile", systemImage: "trash")
                        .font(.title3.weight(.semibold))
                    Text("Deletion removes this profile from PaceBack, destroys its profile-file Keychain key, and requests removal from the local evidence index. Filesystem snapshots or device backups may retain residual encrypted data.")
                        .foregroundStyle(.secondary)
                    Button("Delete \(profile.alias)…", role: .destructive) { confirmDeletion = true }
                        .buttonStyle(.bordered)
                        .paceBackControlTarget()
                        .disabled(!RolePolicy.permits(.deleteProfile, profile: profile))
                }
            }
        }
        .alert("Delete encrypted profile?", isPresented: $confirmDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { _ = await store.deleteSelectedProfile() }
            }
        } message: {
            Text("This removes \(profile.alias) from PaceBack and destroys its profile-file encryption key. The action cannot be reversed in the app.")
        }
    }

    private var roleHandoffCard: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Role handoff").font(.title3.weight(.semibold))
                        Text("Current mode: \(profile.actingRole.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PaceBackDesign.accent)
                            .accessibilityLabel("Current profile mode, \(profile.actingRole.title)")
                    }
                    Spacer()
                    StatusBadge(profile.actingRole.title, kind: .safe)
                }

                Text(roleHandoffExplanation)
                    .foregroundStyle(.secondary)

                roleHandoffActions

                if profile.ageBand.isPediatric || profile.actingRole == .caregiver {
                    Label(
                        "Authentication confirms access to this Mac; it does not verify a person’s identity or legal authority.",
                        systemImage: "person.badge.key"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var roleHandoffActions: some View {
        switch profile.ageBand {
        case .youngChild0To5, .child6To12:
            if profile.actingRole == .guardian {
                handoffButton("Switch to caregiver mode", systemImage: "person.2", target: .caregiver)
            } else {
                handoffButton("Switch to parent or guardian", systemImage: "person.badge.key", target: .guardian)
            }

        case .teen13To17:
            if profile.actingRole == .guardian {
                handoffButton("Hand off to teen", systemImage: "person.crop.circle", target: .teenUser)
            } else {
                handoffButton(
                    "Unlock parent or guardian controls…",
                    systemImage: "lock.open",
                    target: .guardian
                )
            }

        case .adult18To64, .olderAdult65Plus:
            if profile.actingRole == .selfManaged {
                handoffButton(
                    "Hand off to approved caregiver",
                    systemImage: "person.2",
                    target: .caregiver
                )
                .disabled(!profile.caregiverApproved || isSwitchingRole)
                if !profile.caregiverApproved {
                    Text("Approve caregiver access below before handing off this profile.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                handoffButton(
                    "Return to profile-owner mode…",
                    systemImage: "person.badge.key",
                    target: .selfManaged
                )
            }
        }
    }

    private var roleHandoffExplanation: String {
        switch profile.ageBand {
        case .youngChild0To5, .child6To12:
            "A parent, guardian, or caregiver operates this profile. Changing the administering role requires Mac authentication."
        case .teen13To17 where profile.actingRole == .teenUser:
            "Teen mode can use guided sessions, simplification, and age-filtered evidence. A guardian must unlock imports, clipboard reports, deletion, and settings."
        case .teen13To17:
            "Guardian mode can administer the profile. Handing the session to the teen immediately hides protected controls."
        case .adult18To64, .olderAdult65Plus:
            if profile.actingRole == .caregiver {
                "This caregiver session can use recovery tools, import a plan, and copy selected-field reports, but cannot delete the profile, change settings, or confirm extracted plan items."
            } else {
                "This profile is self-managed. Caregiver access is local, explicit, and revocable."
            }
        }
    }

    private func handoffButton(
        _ title: String,
        systemImage: String,
        target: ActingRole
    ) -> some View {
        Button {
            isSwitchingRole = true
            Task {
                _ = await store.switchActingRole(to: target)
                isSwitchingRole = false
            }
        } label: {
            if isSwitchingRole {
                ProgressView().controlSize(.small)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.borderedProminent)
        .paceBackControlTarget()
        .disabled(isSwitchingRole)
        .accessibilityHint("Changes only this local profile’s active role")
    }

    @ViewBuilder
    private var preferenceComposer: some View {
        TextField("Example: prefer shorter paragraphs", text: $preferenceDraft)
            .textFieldStyle(.roundedBorder)
            .paceBackControlTarget()
            .accessibilityHint("Only the text you explicitly add will be saved")
        Button {
            let value = preferenceDraft
            preferenceDraft = ""
            Task { await store.addConfirmedPreference(value) }
        } label: {
            Label("Add preference", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .paceBackControlTarget()
        .disabled(preferenceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct PrivacyArchitectureView: View {
    let profile: LocalProfile

    var body: some View {
        PaceBackCard(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Where this profile can go")
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("A deliberately short data path with a blocked network boundary.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge("On this Mac", kind: .safe)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { architectureNodes }
                    VStack(alignment: .leading, spacing: 12) { architectureNodes }
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { exclusions }
                    VStack(alignment: .leading, spacing: 10) { exclusions }
                }
            }
        }
    }

    @ViewBuilder
    private var architectureNodes: some View {
        PrivacyNode(
            icon: "person.crop.circle",
            title: profile.alias,
            detail: "Alias + age band"
        )
        PrivacyConnector()
        PrivacyNode(
            icon: "key.fill",
            title: "Encrypted profile file",
            detail: "Separate Keychain key"
        )
        PrivacyConnector()
        PrivacyNode(
            icon: "server.rack",
            title: "Local evidence engine",
            detail: "Profile-isolated index"
        )
        PrivacyConnector(blocked: true)
        PrivacyNode(
            icon: "network.slash",
            title: "External services",
            detail: "No profile-data path",
            blocked: true
        )
    }

    @ViewBuilder
    private var exclusions: some View {
        PrivacyExclusion(icon: "person.badge.key", text: "No account")
        PrivacyExclusion(icon: "chart.bar.xaxis", text: "No analytics")
        PrivacyExclusion(icon: "megaphone", text: "No ads or trackers")
        PrivacyExclusion(icon: "globe", text: "No web search")
        PrivacyExclusion(icon: "brain", text: "No live retraining")
    }
}

private struct PrivacyNode: View {
    let icon: String
    let title: String
    let detail: String
    var blocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(blocked ? PaceBackDesign.warm : PaceBackDesign.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(
            (blocked ? PaceBackDesign.warm : PaceBackDesign.accent).opacity(0.07),
            in: RoundedRectangle(cornerRadius: PaceBackDesign.smallCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacyConnector: View {
    var blocked = false

    var body: some View {
        Image(systemName: blocked ? "nosign" : "arrow.right")
            .font(.headline)
            .foregroundStyle(blocked ? PaceBackDesign.warm : Color.secondary.opacity(0.55))
            .accessibilityLabel(blocked ? "Blocked" : "Flows locally to")
    }
}

private struct PrivacyExclusion: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }
}

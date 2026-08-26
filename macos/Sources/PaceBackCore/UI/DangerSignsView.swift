import SwiftUI

struct DangerSignsView: View {
    @Environment(\.dismiss) private var dismiss
    let ageBand: AgeBand

    @State private var selected: Set<DangerSign> = []

    private var result: SafetyGateResult {
        SafetyGate.evaluate(selected: selected, ageBand: ageBand)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaceBackCanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        safetyHeader
                        signChecklist
                        resultPanel
                        sourceFooter
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(30)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Danger-sign check")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 720)
    }

    private var safetyHeader: some View {
        PaceBackCard(style: .prominent, padding: 22) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle().fill(PaceBackDesign.accent.opacity(0.12))
                    Image(systemName: "shield.checkered")
                        .font(.title2)
                        .foregroundStyle(PaceBackDesign.accent)
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Deterministic safety check")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("This screen bypasses every AI system and uses the static age-specific danger-sign list.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        StatusBadge("No AI", kind: .safe)
                        StatusBadge(ageBand.title, kind: .informational)
                    }
                }
            }
        }
    }

    private var signChecklist: some View {
        PaceBackCard(padding: 22) {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select every sign happening now")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("If you are unsure or worried, contact a health professional or emergency service directly.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ForEach(Array(SafetyGate.signs(for: ageBand).enumerated()), id: \.element.id) { index, sign in
                    Toggle(sign.title, isOn: Binding(
                        get: { selected.contains(sign) },
                        set: { isSelected in
                            if isSelected { selected.insert(sign) } else { selected.remove(sign) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .paceBackControlTarget()
                    .accessibilityHint("Updates the emergency instructions immediately")

                    if index < SafetyGate.signs(for: ageBand).count - 1 {
                        Divider().padding(.leading, 26)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        switch result {
        case .clear:
            PaceBackNotice(
                "No danger sign is currently selected. This check cannot rule out an emergency or replace professional judgment.",
                title: "No selected danger signs",
                style: .local
            )

        case .emergency(_, let instructions):
            VStack(alignment: .leading, spacing: 12) {
                Label("Emergency action needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.title.bold())
                Text(instructions)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(.white.opacity(0.7))
                Text("This instruction is static, age-specific, and displayed before any AI feature.")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [PaceBackDesign.critical, Color(red: 0.52, green: 0.06, blue: 0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 1.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits([.isHeader, .isStaticText])
        }
    }

    private var sourceFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(PaceBackDesign.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Source: U.S. Centers for Disease Control and Prevention")
                    .font(.caption.weight(.semibold))
                Link(
                    "Read CDC danger-sign guidance",
                    destination: URL(string: "https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html")!
                )
                .paceBackControlTarget()
                .accessibilityHint("Opens the CDC source in the default browser")
            }
        }
    }
}

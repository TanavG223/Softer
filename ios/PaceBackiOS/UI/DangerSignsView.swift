import SwiftUI

struct DangerSignsView: View {
    let ageBand: AgeBand
    @State private var selected: Set<DangerSign> = []

    private var result: SafetyGateResult {
        SafetyGate.evaluate(selected: selected, ageBand: ageBand)
    }

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    checklist
                    resultPanel
                    source
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Danger signs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        PaceBackCard(style: .prominent) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Deterministic safety check", systemImage: "shield.checkered")
                    .font(.title2.bold())
                Text("Select every sign happening now. This screen uses a static, age-filtered list and never waits for AI.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatusPill(text: "No AI", kind: .local)
                    StatusPill(text: ageBand.title, kind: .informational)
                }
            }
        }
    }

    private var checklist: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Select every sign happening now")
                    .font(.headline)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(SafetyGate.signs(for: ageBand).enumerated()), id: \.element.id) { index, sign in
                    Toggle(isOn: Binding(
                        get: { selected.contains(sign) },
                        set: { enabled in
                            if enabled { selected.insert(sign) } else { selected.remove(sign) }
                        }
                    )) {
                        Text(sign.title)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(PaceBackDesign.critical)
                    .padding(.vertical, 9)
                    .accessibilityHint("Updates the emergency instructions immediately")

                    if index < SafetyGate.signs(for: ageBand).count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        switch result {
        case .clear:
            PaceBackCard(style: .quiet) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("No selected danger signs", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(PaceBackDesign.accent)
                    Text("This checklist cannot rule out an emergency. If you are unsure or worried, contact a health professional or emergency service directly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .emergency(_, let instructions):
            VStack(alignment: .leading, spacing: 12) {
                Label("Emergency action needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.bold())
                Text(instructions)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: URL(string: "tel:911")!) {
                    Label("Call 911", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(PaceBackDesign.critical)
                Text("This instruction is static and appears without consulting an AI model.")
                    .font(.footnote)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [PaceBackDesign.critical, Color(red: 0.48, green: 0.03, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: PaceBackDesign.cornerRadius)
            )
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Source: U.S. Centers for Disease Control and Prevention", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
            Link(
                "Read CDC danger-sign guidance",
                destination: URL(string: "https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html")!
            )
            .font(.footnote)
            .accessibilityHint("Opens the CDC source")
        }
        .foregroundStyle(PaceBackDesign.accent)
    }
}

#Preview("Young child danger signs") {
    NavigationStack {
        DangerSignsView(ageBand: .youngChild0To5)
    }
}

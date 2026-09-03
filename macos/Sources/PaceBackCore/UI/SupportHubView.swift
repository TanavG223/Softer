import AppKit
import SwiftUI

struct SupportHubView: View {
    let store: AppStore
    let ageBand: AgeBand?
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss
    @State private var pendingRoute: SupportRoute?

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    locationBoundary
                    usCrisisSupport
                    immediateDanger
                    humanSupport
                    if ageBand?.isPediatric ?? true {
                        minorGuidance
                    }
                    Text(SupportRoute.boundaryNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("Need help now?")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert(item: $pendingRoute) { route in
            Alert(
                title: Text("Open \(route.title)?"),
                message: Text(
                    "\(route.detail) PaceBack cannot confirm whether the call, text, or website opens or whether support is reached."
                ),
                primaryButton: .default(Text("Open")) {
                    open(route)
                },
                secondaryButton: .cancel {
                    store.clearSupportRoute()
                }
            )
        }
        .accessibilityIdentifier("supportHub")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(PaceBackDesign.accent)
                .frame(width: 60, height: 60)
                .background(PaceBackDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text("STATIC · MODEL-INDEPENDENT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(PaceBackDesign.accent)
                Text("Real people are available")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose the kind of support you need. Opening this page or an option is not used for recommendations or activity feedback.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var locationBoundary: some View {
        PaceBackCard(style: .quiet) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Choose support for your location", systemImage: "globe.americas.fill")
                    .font(.headline)
                Text("The 988 and 911 actions below are for the United States only. If you are elsewhere, use the worldwide directory or call your local emergency number.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                supportButton(.internationalDirectory, prominent: false)
            }
        }
    }

    private var usCrisisSupport: some View {
        PaceBackCard(style: .prominent, padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Mental-health or suicide crisis · U.S. only", systemImage: "phone.bubble.left.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.accent)
                Text("If you may hurt yourself or someone else, or cannot stay safe, call or text 988 or use 988 Lifeline chat.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { crisisButtons }
                    VStack(spacing: 10) { crisisButtons }
                }
            }
        }
    }

    @ViewBuilder
    private var crisisButtons: some View {
        supportButton(.call988, prominent: true)
        supportButton(.text988, prominent: false)
        supportButton(.chat988, prominent: false)
    }

    private var immediateDanger: some View {
        PaceBackCard(style: .caution, padding: 24) {
            VStack(alignment: .leading, spacing: 13) {
                Label("Immediate life-threatening danger · U.S. only", systemImage: "cross.case.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PaceBackDesign.critical)
                Text("Call 911 now or go to the nearest emergency department. Outside the U.S., call your local emergency number.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                supportButton(.immediateDanger, prominent: true, tint: PaceBackDesign.critical)
            }
        }
    }

    private var humanSupport: some View {
        PaceBackCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Other human support")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                supportInformation(.trustedPerson)
                Divider()
                supportInformation(.professionalCare)
            }
        }
    }

    private var minorGuidance: some View {
        PaceBackNotice(
            "If you are a child or teen, tell a trusted adult who can stay with you and help contact support. If the first adult does not help, keep telling safe adults or use urgent support above.",
            title: "For children and teens",
            style: .local
        )
    }

    @ViewBuilder
    private func supportButton(
        _ route: SupportRoute,
        prominent: Bool,
        tint: Color = PaceBackDesign.accent
    ) -> some View {
        let button = Button {
            store.selectSupportRoute(route)
            pendingRoute = route
        } label: {
            Label(route.title, systemImage: symbol(for: route))
                .frame(maxWidth: .infinity)
        }
        if prominent {
            button
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(tint)
                .accessibilityHint("\(route.detail) Requires your confirmation before opening another app or website.")
        } else {
            button
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(tint)
                .accessibilityHint("\(route.detail) Requires your confirmation before opening another app or website.")
        }
    }

    private func supportInformation(_ route: SupportRoute) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol(for: route))
                .font(.headline)
                .foregroundStyle(PaceBackDesign.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.title).font(.headline)
                Text(route.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for route: SupportRoute) -> String {
        switch route {
        case .immediateDanger, .call988: "phone.fill"
        case .text988: "message.fill"
        case .chat988: "bubble.left.and.bubble.right.fill"
        case .internationalDirectory: "globe"
        case .trustedPerson: "person.2.fill"
        case .professionalCare: "person.crop.circle.badge.checkmark"
        }
    }

    private func open(_ route: SupportRoute) {
        defer {
            store.clearSupportRoute()
            pendingRoute = nil
        }
        guard let destination = route.destinationURL else { return }
        NSWorkspace.shared.open(destination)
    }
}

struct PersistentSupportButton: View {
    let store: AppStore
    var compact = false

    var body: some View {
        Group {
            if compact {
                button.buttonStyle(.plain)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .accessibilityHint("Opens U.S.-only 988 and 911 actions plus worldwide support; no model is used")
    }

    private var button: some View {
        Button {
            store.presentedSheet = .support
        } label: {
            Label(compact ? "Help" : "Need help now?", systemImage: "heart.text.square.fill")
        }
    }
}

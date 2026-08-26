import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case focus
    case evidence
    case plan
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .evidence: "Evidence"
        case .plan: "Plan"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .focus: "timer"
        case .evidence: "quote.bubble.fill"
        case .plan: "doc.text.fill"
        case .more: "ellipsis.circle.fill"
        }
    }
}

struct AppShell: View {
    let store: AppStore
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    content(for: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .alert(
            "PaceBack",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { store.lastError = nil }
            },
            message: {
                Text(store.lastError ?? "An unexpected local error occurred.")
            }
        )
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(store: store, selectedTab: $selectedTab)
        case .focus:
            FocusView(store: store)
        case .evidence:
            EvidenceView(store: store)
        case .plan:
            CarePlanView(store: store)
        case .more:
            MoreView(store: store)
        }
    }
}

#Preview("Adult shell") {
    AppShell(store: PreviewFixtures.store())
}

#Preview("Child shell") {
    AppShell(store: PreviewFixtures.store(profile: PreviewFixtures.child))
}

import SwiftUI

@main
struct PaceBackiOSApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .tint(PaceBackDesign.accent)
                .task {
                    await store.load()
                }
        }
    }
}

private struct RootView: View {
    let store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch store.loadingState {
            case .idle, .loading:
                LaunchView()
            case .ready:
                if store.profiles.isEmpty {
                    OnboardingView(store: store)
                } else if !store.modelPackStatus.isReady && !store.engineAvailability.isReady {
                    ModelSetupView(store: store, isRequired: true)
                } else {
                    AppShell(store: store)
                }
            case .failed(let message):
                StorageFailureView(message: message, store: store)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.loadingState)
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            VStack(spacing: 18) {
                PaceBackMark(size: 74)
                Text("PaceBack")
                    .font(.largeTitle.bold())
                ProgressView("Opening encrypted workspace…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct StorageFailureView: View {
    let message: String
    let store: AppStore

    var body: some View {
        ZStack {
            PaceBackCanvasBackground()
            VStack(spacing: 18) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 46))
                    .foregroundStyle(PaceBackDesign.warm)
                    .accessibilityHidden(true)
                Text("Encrypted workspace unavailable")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task {
                        store.loadingState = .idle
                        await store.load()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
    }
}

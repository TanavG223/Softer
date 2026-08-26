import AppKit
import PaceBackCore
import SwiftUI

@MainActor
final class PaceBackAppDelegate: NSObject, NSApplicationDelegate {
    var stopSidecar: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The research build is distributed directly rather than through the
        // App Store. Explicit activation keeps launches from Finder, `open`,
        // and clean test machines consistent and brings the recovery window
        // forward without waiting for the local AI helper to initialize.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopSidecar?()
    }
}

@main
@MainActor
struct PaceBackDesktopApp: App {
    @NSApplicationDelegateAdaptor(PaceBackAppDelegate.self) private var appDelegate
    @State private var store: AppStore
    private let runtime: SidecarEngineRuntime

    init() {
        let runtime = SidecarEngineRuntime()
        self.runtime = runtime
        _store = State(initialValue: AppStore(aiEngine: runtime.engine))
    }

    var body: some Scene {
        WindowGroup {
            PaceBackRootView(store: store, sidecarState: runtime.state)
                .frame(minWidth: 900, minHeight: 650)
                .task {
                    appDelegate.stopSidecar = { [runtime] in runtime.stop() }
                    await runtime.start()
                }
        }
        .defaultSize(width: 1_180, height: 780)
        .commands {
            PaceBackCommands(store: store)
        }

        Settings {
            PaceBackSettingsView(store: store)
        }
    }
}

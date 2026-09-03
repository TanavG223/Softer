import AppKit
import PaceBackCore
import SwiftUI

@MainActor
final class PaceBackAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Explicit activation keeps launches from Finder, `open`, and clean
        // test machines consistent. The wellbeing activities are fully native
        // and do not wait for a helper process or downloaded model.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        restoreOffscreenWindows()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        restoreOffscreenWindows()
    }

    private func restoreOffscreenWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let visibleFrames = NSScreen.screens.map(\.visibleFrame)
            for window in NSApp.windows where window.canBecomeMain {
                let visibleArea = visibleFrames
                    .map { window.frame.intersection($0) }
                    .filter { !$0.isNull }
                    .map { $0.width * $0.height }
                    .max() ?? 0
                guard visibleArea < 10_000 else { continue }
                let size = window.frame.size
                let origin = NSPoint(
                    x: screen.visibleFrame.midX - size.width / 2,
                    y: screen.visibleFrame.midY - size.height / 2
                )
                window.setFrameOrigin(origin)
            }
        }
    }

}

@main
@MainActor
struct PaceBackDesktopApp: App {
    @NSApplicationDelegateAdaptor(PaceBackAppDelegate.self) private var appDelegate
    @State private var store: AppStore

    init() {
        _store = State(initialValue: AppStore())
    }

    var body: some Scene {
        WindowGroup {
            PaceBackRootView(store: store)
                .frame(minWidth: 900, minHeight: 650)
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

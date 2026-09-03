import SwiftUI

public struct PaceBackSettingsView: View {
    let store: AppStore

    public init(store: AppStore) { self.store = store }

    public var body: some View {
        @Bindable var preferences = store.preferences
        TabView {
            Form {
                Section("Text and layout") {
                    Slider(value: $preferences.textScale, in: 0.9...2.0, step: 0.1) {
                        Text("Text and control scale")
                    } minimumValueLabel: {
                        Text("A")
                    } maximumValueLabel: {
                        Text("A").font(.title2)
                    }
                    Text("Current scale: \(preferences.textScale.formatted(.number.precision(.fractionLength(1))))×")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Toggle("Use comfortable spacing", isOn: $preferences.comfortableSpacing)
                        .paceBackControlTarget()
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Display", systemImage: "textformat.size") }

            Form {
                Section("Motion and access") {
                    Toggle("Always reduce app motion", isOn: $preferences.reduceMotionOverride)
                        .paceBackControlTarget()
                    Label("PaceBack also follows macOS Reduce Motion, Reduce Transparency, and Increase Contrast.", systemImage: "accessibility")
                    Label("Games work with tap or keyboard controls; dragging is optional.", systemImage: "keyboard")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Accessibility", systemImage: "accessibility") }

            Form {
                Section("Boundaries") {
                    Label("No diagnosis, treatment, passive mood inference, score, or promised outcome.", systemImage: "hand.raised")
                    Label("Game moves and support choices never alter recommendations.", systemImage: "eye.slash")
                    Label("Optional closed check-outs stay in the encrypted local profile.", systemImage: "lock.shield")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .paceBackTextScale(store.preferences.textScale)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 430, idealHeight: 500)
    }
}

public struct PaceBackCommands: Commands {
    private let store: AppStore

    public init(store: AppStore) { self.store = store }

    public var body: some Commands {
        CommandMenu("Wellbeing") {
            Button("Calm") { store.selectedSection = .calm }
                .keyboardShortcut("1", modifiers: .command)
            Button("Toolkit") { store.selectedSection = .toolkit }
                .keyboardShortcut("2", modifiers: .command)
            Button("Play") { store.selectedSection = .play }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Need help now") { store.presentedSheet = .support }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}

import AppKit
import SwiftUI
import KumoCoreKit

@main
struct KumoApp: App {
    @State private var store = KumoAppStore()
    @NSApplicationDelegateAdaptor(KumoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            KumoRootView(store: store)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Kumo") {
                    KumoAppContext.shared.openAboutWindow()
                }
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            CommandMenu("Control") {
                Button("Start Kumo") {
                    Task { await store.startCore() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.isLoading || store.status.state == .running || store.status.state == .starting)

                Button("Stop Kumo") {
                    store.stopCore()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(store.isLoading || store.status.state != .running)

                Divider()

                Button("Rule Mode") {
                    Task { await store.setMode(.rule) }
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(store.isLoading || store.isSwitchingMode || store.status.state != .running || store.status.mode == .rule)

                Button("Global Mode") {
                    Task { await store.setMode(.global) }
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(store.isLoading || store.isSwitchingMode || store.status.state != .running || store.status.mode == .global)

                Button("Direct Mode") {
                    Task { await store.setMode(.direct) }
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(store.isLoading || store.isSwitchingMode || store.status.state != .running || store.status.mode == .direct)

                Divider()

                Button("Refresh Kumo") {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isLoading)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }

        Window("About Kumo", id: "about") {
            AboutView()
                .environment(store)
        }
        .defaultSize(width: 440, height: 380)
        .windowResizability(.contentMinSize)
    }
}

private struct KumoRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let store: KumoAppStore

    var body: some View {
        ContentView()
            .environment(store)
            .frame(minWidth: 820, minHeight: 560)
            .task {
                KumoAppContext.shared.attach(store: store)
                KumoAppContext.shared.attachWindowActions {
                    openWindow(id: "main")
                } openSettings: {
                    openSettings()
                } openAboutWindow: {
                    openWindow(id: "about")
                }
            }
    }
}

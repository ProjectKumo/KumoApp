import AppKit
import SwiftUI
import KumoCoreKit

@main
struct KumoApp: App {
    @State private var store: KumoAppStore
    @State private var subStore: SubStoreStore
    @State private var navigation = KumoNavigationState()
    @NSApplicationDelegateAdaptor(KumoAppDelegate.self) private var appDelegate

    init() {
        let appStore = KumoAppStore()
        _store = State(initialValue: appStore)
        _subStore = State(initialValue: SubStoreStore(controller: appStore.controller))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            KumoRootView(store: store, subStore: subStore, navigation: navigation)
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

                Button(store.status.systemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy") {
                    store.setSystemProxyEnabled(!store.status.systemProxyEnabled)
                }
                .keyboardShortcut("p", modifiers: [.command, .control])
                .disabled(store.isLoading || (store.status.state != .running && !store.status.systemProxyEnabled))

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

            CommandMenu("Navigate") {
                navigationButton("Overview", destination: .overview, key: "1")
                navigationButton("Profiles", destination: .profiles, key: "2")
                navigationButton("Proxies", destination: .proxies, key: "3")

                Divider()

                navigationButton("Connections", destination: .connections, key: "4")
                navigationButton("Logs", destination: .logs, key: "5")
                navigationButton("Rules", destination: .rules, key: "6")

                Divider()

                navigationButton("Core", destination: .core, key: "7")
                navigationButton("System Proxy", destination: .systemProxy, key: "8")
                navigationButton("Sub-Store", destination: .subStore, key: "9")
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

private extension KumoApp {
    func navigationButton(_ title: String, destination: SidebarDestination, key: KeyEquivalent) -> some View {
        Button(title) {
            navigation.selection = destination
            KumoAppContext.shared.openMainWindow()
        }
        .keyboardShortcut(key, modifiers: [.command, .option])
    }
}

private struct KumoRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let store: KumoAppStore
    let subStore: SubStoreStore
    let navigation: KumoNavigationState

    var body: some View {
        ContentView()
            .environment(store)
            .environment(subStore)
            .environment(navigation)
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

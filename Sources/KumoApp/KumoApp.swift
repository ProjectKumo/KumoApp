import AppKit
import SwiftUI
import KumoCoreKit

@main
struct KumoApp: App {
    @State private var store: KumoAppStore
    @State private var subStore: SubStoreStore
    @State private var navigation = KumoNavigationState()
    @State private var localizationManager: LocalizationManager
    @NSApplicationDelegateAdaptor(KumoAppDelegate.self) private var appDelegate

    init() {
        let appStore = KumoAppStore()
        let prefs = appStore.controller.userPreferences()
        let locManager = LocalizationManager(preferences: prefs)
        appStore.localizationManager = locManager
        _store = State(initialValue: appStore)
        _subStore = State(initialValue: SubStoreStore(controller: appStore.controller))
        _localizationManager = State(initialValue: locManager)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            KumoRootView(store: store, subStore: subStore, navigation: navigation)
                .environment(localizationManager)
                .environment(\.locale, localizationManager.locale)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About Kumo")) {
                    KumoAppContext.shared.openAboutWindow()
                }
            }

            CommandGroup(after: .toolbar) {
                Button(String(localized: "Toggle Sidebar")) {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            CommandMenu(String(localized: "Control")) {
                Button(String(localized: "Start Kumo")) {
                    Task { await store.startCore() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.isLoading || store.status.state == .running || store.status.state == .starting)

                Button(String(localized: "Stop Kumo")) {
                    store.stopCore()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(store.isLoading || store.status.state != .running)

                Divider()

                if store.status.systemProxyEnabled {
                    Button(String(localized: "Disable System Proxy")) {
                        store.setSystemProxyEnabled(false)
                    }
                    .keyboardShortcut("p", modifiers: [.command, .control])
                    .disabled(store.isLoading || store.status.state != .running)
                } else {
                    Button(String(localized: "Enable System Proxy")) {
                        store.setSystemProxyEnabled(true)
                    }
                    .keyboardShortcut("p", modifiers: [.command, .control])
                    .disabled(store.isLoading || store.status.state != .running)
                }

                Divider()

                Button(String(localized: "Rule Mode")) {
                    Task { await store.setMode(.rule) }
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(store.isLoading || store.isSwitchingMode || store.status.state != .running || store.status.mode == .rule)

                Button(String(localized: "Global Mode")) {
                    Task { await store.setMode(.global) }
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(store.isLoading || store.isSwitchingMode || store.status.state != .running || store.status.mode == .global)

                Button(String(localized: "Direct Mode")) {
                    Task { await store.setMode(.direct) }
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(store.isLoading || store.isSwitchingMode || store.status.state != .running || store.status.mode == .direct)

                Divider()

                Button(String(localized: "Refresh Kumo")) {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isLoading)
            }

            CommandMenu(String(localized: "Navigate")) {
                navigationButton(String(localized: "Overview"), destination: .overview, key: "1")
                navigationButton(String(localized: "Profiles"), destination: .profiles, key: "2")
                navigationButton(String(localized: "Proxies"), destination: .proxies, key: "3")

                Divider()

                navigationButton(String(localized: "Connections"), destination: .connections, key: "4")
                navigationButton(String(localized: "Logs"), destination: .logs, key: "5")
                navigationButton(String(localized: "Rules"), destination: .rules, key: "6")

                Divider()

                navigationButton(String(localized: "Core"), destination: .core, key: "7")
                navigationButton(String(localized: "System Proxy"), destination: .systemProxy, key: "8")
                navigationButton(String(localized: "Sub-Store"), destination: .subStore, key: "9")
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(localizationManager)
                .environment(\.locale, localizationManager.locale)
        }

        Window("About Kumo", id: "about") {
            AboutView()
                .environment(store)
                .environment(localizationManager)
                .environment(\.locale, localizationManager.locale)
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
    @Bindable var store: KumoAppStore
    let subStore: SubStoreStore
    let navigation: KumoNavigationState

    var body: some View {
        ContentView()
            .environment(store)
            .environment(subStore)
            .environment(navigation)
            .frame(minWidth: 820, minHeight: 560)
            .sheet(isPresented: $store.showOnboarding) {
                OnboardingView()
                    .environment(store)
            }
            .task {
                KumoAppContext.shared.attach(store: store)
                KumoAppContext.shared.attachWindowActions {
                    openWindow(id: "main")
                } openSettings: {
                    openSettings()
                } openAboutWindow: {
                    openWindow(id: "about")
                }
                store.startUpdatePolling()
                store.startProfileUpdatePolling()
            }
    }
}

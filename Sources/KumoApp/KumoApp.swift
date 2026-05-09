import AppKit
import SwiftUI
import KumoCoreKit

@main
struct KumoApp: App {
    @State private var store = KumoAppStore()
    @NSApplicationDelegateAdaptor(KumoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    KumoAppContext.shared.attach(store: store)
                }
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
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
                .disabled(store.isLoading || store.status.state != .running || store.status.mode == .rule)

                Button("Global Mode") {
                    Task { await store.setMode(.global) }
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(store.isLoading || store.status.state != .running || store.status.mode == .global)

                Button("Direct Mode") {
                    Task { await store.setMode(.direct) }
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(store.isLoading || store.status.state != .running || store.status.mode == .direct)

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

        MenuBarExtra("Kumo", systemImage: menuBarSymbol) {
            KumoMenuBarContent()
                .environment(store)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        switch store.status.state {
        case .running: "cloud.fill"
        case .starting: "cloud.bolt"
        case .failed: "cloud.slash"
        case .stopped: "cloud"
        }
    }
}

private struct KumoMenuBarContent: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Section("Status") {
            Text("Core: \(store.status.state.rawValue.capitalized)")
            Text("Profile: \(store.currentProfile?.name ?? "Default")")
            Text("Mode: \(store.status.mode.displayName)")
        }

        Section {
            Button("Open Kumo") {
                openMainWindow()
            }
            .keyboardShortcut("0", modifiers: .command)

            Button(store.status.state == .running ? "Stop Kumo" : "Start Kumo") {
                if store.status.state == .running {
                    store.stopCore()
                } else {
                    Task { await store.startCore() }
                }
            }
            .disabled(store.isLoading)
        }

        Section {
            Picker("Mode", selection: Binding {
                store.status.mode
            } set: { mode in
                Task { await store.setMode(mode) }
            }) {
                ForEach(OutboundMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(store.isLoading || store.status.state != .running)

            Button(store.status.systemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy") {
                store.setSystemProxyEnabled(!store.status.systemProxyEnabled)
            }
            .disabled(store.isLoading || (store.status.state != .running && !store.status.systemProxyEnabled))
        }

        if !store.profiles.isEmpty {
            Menu("Profiles") {
                ForEach(store.profiles.prefix(8)) { profile in
                    Button(profile.isCurrent ? "\(profile.name) (Current)" : profile.name) {
                        Task { await store.selectProfile(profile) }
                    }
                    .disabled(profile.isCurrent || store.isLoading)
                }
            }
        }

        if !store.proxyGroups.isEmpty {
            Menu("Proxy Groups") {
                ForEach(store.proxyGroups.prefix(5)) { group in
                    Menu(group.name) {
                        ForEach(group.proxies.prefix(12)) { proxy in
                            Button(group.selectedProxyName == proxy.name ? "\(proxy.name) (Selected)" : proxy.name) {
                                Task { await store.selectProxy(group: group, proxy: proxy) }
                            }
                            .disabled(group.selectedProxyName == proxy.name || store.isLoading)
                        }
                    }
                }
            }
        }

        Divider()

        Section {
            Button("Refresh") {
                Task { await store.refreshAll() }
            }
            .disabled(store.isLoading)

            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("About Kumo") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }

        Divider()

        Button("Quit Kumo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.contentViewController != nil }),
           !existing.isMiniaturized {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

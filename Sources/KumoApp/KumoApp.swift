import AppKit
import SwiftUI
import KumoCoreKit

@main
struct KumoApp: App {
    @State private var store = KumoAppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApplication.shared.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApplication.shared.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    NSApplication.shared.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("Select All") {
                    NSApplication.shared.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
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
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isLoading)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra("Kumo", systemImage: "cloud") {
            Text("Kumo: \(store.status.state.rawValue.capitalized)")
            Text("Profile: \(store.currentProfile?.name ?? "Default")")
            Button(store.status.state == .running ? "Stop Kumo" : "Start Kumo") {
                if store.status.state == .running {
                    store.stopCore()
                } else {
                    Task { await store.startCore() }
                }
            }
            .disabled(store.isLoading)
            Divider()
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
            Button("Refresh") {
                Task { await store.refreshAll() }
            }
            .disabled(store.isLoading)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

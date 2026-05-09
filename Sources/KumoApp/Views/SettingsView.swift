import SwiftUI

struct SettingsView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                Form {
                    Section("Status") {
                        LabeledContent("Profile", value: store.currentProfile?.name ?? "Default")
                        LabeledContent("Mode", value: store.status.mode.displayName)
                        LabeledContent("System Proxy", value: store.status.systemProxyEnabled ? "On" : "Off")
                    }
                    Section("Actions") {
                        Button("Refresh") {
                            Task { await store.refreshAll() }
                        }
                    }
                }
                .formStyle(.grouped)
                .scenePadding()
            }

            Tab("Core", systemImage: "cpu") {
                Form {
                    Section("Mihomo") {
                        LabeledContent("State", value: store.status.state.rawValue.capitalized)
                        LabeledContent("Version", value: store.coreConfiguration.version ?? "-")
                        LabeledContent("Controller", value: "\(store.status.endpoint.host):\(store.status.endpoint.port)")
                        LabeledContent("Mixed Port", value: "\(store.status.proxyPorts.mixedPort)")
                    }
                    Section("Advanced") {
                        LabeledContent("TUN", value: store.coreConfiguration.tunEnabled ? "On" : "Off")
                        LabeledContent("DNS", value: store.coreConfiguration.dnsEnabled ? "On" : "Off")
                        LabeledContent("Sniffer", value: store.coreConfiguration.snifferEnabled ? "On" : "Off")
                    }
                }
                .formStyle(.grouped)
                .scenePadding()
            }
        }
        .kumoLiquidGlassTabViewStyle()
        .frame(width: 520, height: 360)
        .task {
            await store.refreshAll()
        }
    }
}

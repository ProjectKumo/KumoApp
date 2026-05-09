import SwiftUI
import UniformTypeIdentifiers

struct CoreView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var isChoosingCore = false

    var body: some View {
        KumoPage(title: "Core") {
            Form {
                Section {
                    LabeledContent("State", value: store.status.state.rawValue.capitalized)
                    LabeledContent("Core", value: store.status.corePath.map(shortPath) ?? "Auto")
                    LabeledContent("Version", value: store.coreConfiguration.version ?? "-")
                    LabeledContent("Controller", value: "\(store.status.endpoint.host):\(store.status.endpoint.port)")
                    LabeledContent("Mixed Port", value: "\(store.coreConfiguration.mixedPort)")
                    LabeledContent("Log Level", value: store.coreConfiguration.logLevel)
                }

                Section("Core Binary") {
                    if store.coreCandidates.isEmpty {
                        CompactSettingRow(title: "No core found", detail: "Install mihomo or choose a binary.") {
                            HStack {
                                installCoreButton
                                Button("Choose") {
                                    isChoosingCore = true
                                }
                            }
                        }
                    } else {
                        Picker("Selected Core", selection: corePathBinding) {
                            Text("Auto").tag("")
                            ForEach(store.coreCandidates) { candidate in
                                Text("\(candidate.name) · \(candidate.sourceDescription)")
                                    .tag(candidate.path)
                            }
                        }

                        Button("Choose File") {
                            isChoosingCore = true
                        }

                        installCoreButton
                    }
                }

            }
            .formStyle(.grouped)
        }
        .fileImporter(
            isPresented: $isChoosingCore,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            store.setCorePath(url.path)
        }
        .task {
            store.refreshCoreCandidates()
            await store.loadCoreConfiguration()
        }
    }

    private var corePathBinding: Binding<String> {
        Binding {
            store.status.corePath ?? ""
        } set: { path in
            guard !path.isEmpty else {
                return
            }
            store.setCorePath(path)
        }
    }

    private var installCoreButton: some View {
        Button {
            Task {
                await store.installManagedCore()
            }
        } label: {
            if store.isInstallingCore {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Install Latest")
            }
        }
        .disabled(store.isInstallingCore)
        .help("Download the latest Mihomo core for this Mac and store it in Kumo's Application Support directory.")
    }

    private func shortPath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct SystemProxyView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        KumoPage(title: "System Proxy") {
            Form {
                Section {
                    Toggle("Enable System Proxy", isOn: Binding {
                        store.status.systemProxyEnabled
                    } set: { isEnabled in
                        store.setSystemProxyEnabled(isEnabled)
                    })
                    LabeledContent("Host", value: store.status.endpoint.host)
                    LabeledContent("Port", value: "\(store.status.proxyPorts.mixedPort)")
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct DNSView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        ConfigurationStubView(
            title: "DNS",
            rows: [
                ("Managed", store.coreConfiguration.dnsEnabled ? "On" : "Off"),
                ("Mode", "Configured in profile")
            ]
        )
    }
}

struct TunView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        ConfigurationStubView(
            title: "TUN",
            rows: [
                ("Enabled", store.coreConfiguration.tunEnabled ? "On" : "Off"),
                ("Stack", "Profile")
            ]
        )
    }
}

struct SnifferView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        ConfigurationStubView(
            title: "Sniffer",
            rows: [
                ("Enabled", store.coreConfiguration.snifferEnabled ? "On" : "Off"),
                ("Rules", "Profile")
            ]
        )
    }
}

struct ResourcesView: View {
    var body: some View {
        ConfigurationStubView(
            title: "Resources",
            rows: [
                ("Proxy Providers", "Not configured"),
                ("Rule Providers", "Not configured"),
                ("Geo Data", "Profile")
            ]
        )
    }
}

struct OverridesView: View {
    var body: some View {
        ConfigurationStubView(
            title: "Overrides",
            rows: [
                ("Files", "Not configured"),
                ("Transform", "Coming next")
            ]
        )
    }
}

struct SubStoreView: View {
    var body: some View {
        ConfigurationStubView(
            title: "Sub-Store",
            rows: [
                ("Backend", "Not configured"),
                ("Sync", "Coming next")
            ]
        )
    }
}

private struct ConfigurationStubView: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        KumoPage(title: title) {
            Form {
                Section {
                    ForEach(rows, id: \.0) { row in
                        LabeledContent(row.0, value: row.1)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct CoreView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var isChoosingCore = false
    @State private var runtimeDraft = CoreRuntimeSettings()

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

                Section {
                    TextField("Mixed Port", value: mixedPortBinding, format: .number)
                    Picker("Log Level", selection: logLevelBinding) {
                        Text("Silent").tag("silent")
                        Text("Error").tag("error")
                        Text("Warning").tag("warning")
                        Text("Info").tag("info")
                        Text("Debug").tag("debug")
                    }
                    Toggle("Allow LAN", isOn: allowLANBinding)
                    Toggle("IPv6", isOn: ipv6Binding)
                    ControllerSecretField(
                        currentSecret: store.status.endpoint.secret,
                        commit: { store.setControllerSecret($0) }
                    )
                    HStack {
                        Spacer()
                        Button("Reset") {
                            resetRuntimeDraft()
                        }
                        .disabled(!hasRuntimeDraftChanges || store.isLoading)

                        Button("Apply") {
                            applyRuntimeDraft()
                        }
                        .disabled(!hasRuntimeDraftChanges || store.isLoading)
                    }
                } header: {
                    Text("Runtime Settings")
                } footer: {
                    Text("Changes are staged locally until you apply them. Kumo-owned runtime keys are written through the shared controller layer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            Text("Auto").tag(String?.none)
                            ForEach(store.coreCandidates) { candidate in
                                Text("\(candidate.name) · \(candidate.sourceDescription)")
                                    .tag(String?.some(candidate.path))
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
            resetRuntimeDraft()
        }
        .onChange(of: runtimeSettings) { oldValue, newValue in
            if runtimeDraft == oldValue {
                runtimeDraft = newValue
            }
        }
    }

    private var corePathBinding: Binding<String?> {
        Binding {
            store.status.corePath
        } set: { path in
            if let path, !path.isEmpty {
                store.setCorePath(path)
            } else {
                store.clearCorePath()
            }
        }
    }

    private var runtimeSettings: CoreRuntimeSettings {
        store.status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: store.status.proxyPorts.mixedPort)
    }

    private var hasRuntimeDraftChanges: Bool {
        normalizedRuntimeDraft != runtimeSettings
    }

    private var normalizedRuntimeDraft: CoreRuntimeSettings {
        var settings = runtimeDraft
        settings.mixedPort = max(1, min(65535, settings.mixedPort))
        return settings
    }

    private var mixedPortBinding: Binding<Int> {
        Binding {
            runtimeDraft.mixedPort
        } set: { value in
            runtimeDraft.mixedPort = max(1, min(65535, value))
        }
    }

    private var logLevelBinding: Binding<String> {
        Binding {
            runtimeDraft.logLevel
        } set: { value in
            runtimeDraft.logLevel = value
        }
    }

    private var allowLANBinding: Binding<Bool> {
        Binding {
            runtimeDraft.allowLAN
        } set: { value in
            runtimeDraft.allowLAN = value
        }
    }

    private var ipv6Binding: Binding<Bool> {
        Binding {
            runtimeDraft.ipv6
        } set: { value in
            runtimeDraft.ipv6 = value
        }
    }

    private func resetRuntimeDraft() {
        runtimeDraft = runtimeSettings
    }

    private func applyRuntimeDraft() {
        let settings = normalizedRuntimeDraft
        runtimeDraft = settings
        Task { await store.updateRuntimeSettings(settings) }
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


import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct SystemProxyView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var systemProxyDraft = SystemProxySettings()

    var body: some View {
        KumoPage(title: "System Proxy") {
            Form {
                Section {
                    Toggle("Enable System Proxy", isOn: Binding {
                        store.status.systemProxyEnabled
                    } set: { isEnabled in
                        store.setSystemProxyEnabled(isEnabled)
                    })
                    TextField("Network Service", text: networkServiceBinding)
                    TextField("Host", text: hostBinding)
                    TextField("Port", value: portBinding, format: .number)
                    Picker("Mode", selection: modeBinding) {
                        ForEach(SystemProxyMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Text("System Proxy updates macOS proxy settings through networksetup. It does not add a VPN configuration; helper installation uses the administrator authorization prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Reset") {
                            resetSystemProxyDraft()
                        }
                        .disabled(!hasSystemProxyDraftChanges)

                        Button("Apply") {
                            applySystemProxyDraft()
                        }
                        .disabled(!hasSystemProxyDraftChanges)
                    }
                } footer: {
                    Text("Network service, host, port, mode, bypass, and PAC script changes are staged until you apply them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if systemProxyDraft.mode == .manual {
                    Section("Bypass") {
                        EditableStringList(
                            items: $systemProxyDraft.bypassList,
                            placeholder: "Domain, host, or CIDR",
                            monospaced: true,
                            accessibilityLabel: "Bypass entries"
                        )
                        Button("Add Defaults") {
                            mergeBypassDefaults()
                        }
                    }
                }

                if systemProxyDraft.mode == .pac {
                    Section {
                        TextEditor(text: $systemProxyDraft.pacScript)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                    } header: {
                        Text("PAC Script")
                    } footer: {
                        Text("Kumo serves the PAC script from a local HTTP listener and points macOS at it via networksetup -setautoproxyurl. Enable System Proxy to (re)apply changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task {
            resetSystemProxyDraft()
        }
        .onChange(of: systemProxySettings) { oldValue, newValue in
            if systemProxyDraft == oldValue {
                systemProxyDraft = newValue
            }
        }
    }

    private var systemProxySettings: SystemProxySettings {
        store.status.systemProxySettings ?? SystemProxySettings(
            host: store.status.endpoint.host,
            port: store.status.proxyPorts.mixedPort
        )
    }

    private var hasSystemProxyDraftChanges: Bool {
        normalizedSystemProxyDraft != systemProxySettings
    }

    private var normalizedSystemProxyDraft: SystemProxySettings {
        var settings = systemProxyDraft
        settings.networkService = settings.networkService.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.port = max(1, min(65535, settings.port))
        settings.bypassList = settings.bypassList
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return settings
    }

    private var networkServiceBinding: Binding<String> {
        Binding {
            systemProxyDraft.networkService
        } set: { value in
            systemProxyDraft.networkService = value
        }
    }

    private var hostBinding: Binding<String> {
        Binding {
            systemProxyDraft.host
        } set: { value in
            systemProxyDraft.host = value
        }
    }

    private var portBinding: Binding<Int> {
        Binding {
            systemProxyDraft.port
        } set: { value in
            systemProxyDraft.port = max(1, min(65535, value))
        }
    }

    private var modeBinding: Binding<SystemProxyMode> {
        Binding {
            systemProxyDraft.mode
        } set: { value in
            systemProxyDraft.mode = value
        }
    }

    private func resetSystemProxyDraft() {
        systemProxyDraft = systemProxySettings
    }

    private func mergeBypassDefaults() {
        let merged = Array(Set(systemProxyDraft.bypassList + SystemProxySettings.defaultBypassList)).sorted()
        systemProxyDraft.bypassList = merged
    }

    private func applySystemProxyDraft() {
        let settings = normalizedSystemProxyDraft
        systemProxyDraft = settings
        store.updateSystemProxySettings(settings)
    }
}

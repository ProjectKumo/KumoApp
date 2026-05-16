import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct SystemProxyView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var systemProxyDraft = SystemProxySettings()
    @State private var bypassTextDraft = SystemProxySettings.defaultBypassList
        .joined(separator: "\n")

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
                        TextEditor(text: $bypassTextDraft)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                            .onChange(of: bypassTextDraft) { _, newValue in
                                systemProxyDraft.bypassList = Self.bypassList(from: newValue)
                            }
                        Button("Add Defaults") {
                            let bypassList = Self.bypassList(from: bypassTextDraft)
                            updateBypassList(
                                Array(Set(bypassList + SystemProxySettings.defaultBypassList)).sorted()
                            )
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
                updateSystemProxyDraft(newValue)
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
        settings.bypassList = Self.bypassList(from: bypassTextDraft)
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

    private static func bypassText(from bypassList: [String]) -> String {
        bypassList.joined(separator: "\n")
    }

    private static func bypassList(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resetSystemProxyDraft() {
        updateSystemProxyDraft(systemProxySettings)
    }

    private func updateSystemProxyDraft(_ settings: SystemProxySettings) {
        systemProxyDraft = settings
        bypassTextDraft = Self.bypassText(from: settings.bypassList)
    }

    private func updateBypassList(_ bypassList: [String]) {
        systemProxyDraft.bypassList = bypassList
        bypassTextDraft = Self.bypassText(from: bypassList)
    }

    private func applySystemProxyDraft() {
        let settings = normalizedSystemProxyDraft
        updateSystemProxyDraft(settings)
        store.updateSystemProxySettings(settings)
    }
}


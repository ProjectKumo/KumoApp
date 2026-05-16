import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct SnifferView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void
    @State private var snifferDraft = SnifferSettings()

    var body: some View {
        KumoPage(title: "Sniffer") {
            Form {
                Section("Status") {
                    Toggle("Enable Sniffer", isOn: Binding {
                        currentSnifferSettings.isEnabled
                    } set: { isEnabled in
                        Task { await store.setSnifferEnabled(isEnabled) }
                    })
                    .disabled(store.isLoading)
                }

                Section("Behavior") {
                    Toggle("Override Destination", isOn: $snifferDraft.overrideDestination)
                    Toggle("HTTP Override Destination", isOn: $snifferDraft.httpOverrideDestination)
                    Toggle("Force DNS Mapping", isOn: $snifferDraft.forceDNSMapping)
                    Toggle("Parse Pure IP", isOn: $snifferDraft.parsePureIP)
                }

                Section("HTTP Ports") {
                    EditableIntList(
                        values: $snifferDraft.httpPorts,
                        placeholder: "Port (1–65535)",
                        accessibilityLabel: "HTTP ports"
                    )
                }

                Section("TLS Ports") {
                    EditableIntList(
                        values: $snifferDraft.tlsPorts,
                        placeholder: "Port (1–65535)",
                        accessibilityLabel: "TLS ports"
                    )
                }

                Section("QUIC Ports") {
                    EditableIntList(
                        values: $snifferDraft.quicPorts,
                        placeholder: "Port (1–65535)",
                        accessibilityLabel: "QUIC ports"
                    )
                }

                Section("Skip Domain") {
                    EditableStringList(
                        items: $snifferDraft.skipDomain,
                        placeholder: "+.example.com",
                        monospaced: true,
                        accessibilityLabel: "Skip domain"
                    )
                }

                Section("Force Domain") {
                    EditableStringList(
                        items: $snifferDraft.forceDomain,
                        placeholder: "+.example.com",
                        monospaced: true,
                        accessibilityLabel: "Force domain"
                    )
                }

                Section("Skip Destination Address") {
                    EditableStringList(
                        items: $snifferDraft.skipDstAddress,
                        placeholder: "10.0.0.0/8",
                        monospaced: true,
                        accessibilityLabel: "Skip destination address"
                    )
                }

                Section("Skip Source Address") {
                    EditableStringList(
                        items: $snifferDraft.skipSrcAddress,
                        placeholder: "10.0.0.0/8",
                        monospaced: true,
                        accessibilityLabel: "Skip source address"
                    )
                }

                Section {
                    if let validationMessage = snifferDraftValidationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button("Reset") {
                            updateSnifferDraft(currentSnifferSettings)
                        }
                        .disabled(!hasSnifferDraftChanges || store.isLoading)

                        Button("Apply") {
                            applySnifferDraft()
                        }
                        .disabled(!canApplySnifferDraft)
                    }
                } footer: {
                    Text("Sniffer changes are staged locally. Apply restarts the core when it is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .task {
            updateSnifferDraft(currentSnifferSettings)
        }
        .onChange(of: currentSnifferSettings) { _, newValue in
            if !hasSnifferDraftChanges {
                updateSnifferDraft(newValue)
            } else {
                snifferDraft.isEnabled = newValue.isEnabled
            }
        }
    }

    private var currentSnifferSettings: SnifferSettings {
        store.status.runtimeSettings?.sniffer ?? SnifferSettings()
    }

    private var hasSnifferDraftChanges: Bool {
        normalizedSnifferDraft != currentSnifferSettings
    }

    private var canApplySnifferDraft: Bool {
        hasSnifferDraftChanges && snifferDraftValidationMessage == nil && !store.isLoading
    }

    private var normalizedSnifferDraft: SnifferSettings {
        var settings = snifferDraft
        settings.httpPorts = settings.httpPorts.filter { $0 > 0 && $0 <= 65535 }
        settings.tlsPorts = settings.tlsPorts.filter { $0 > 0 && $0 <= 65535 }
        settings.quicPorts = settings.quicPorts.filter { $0 > 0 && $0 <= 65535 }
        settings.skipDomain = Self.normalizedList(settings.skipDomain)
        settings.forceDomain = Self.normalizedList(settings.forceDomain)
        settings.skipDstAddress = Self.normalizedList(settings.skipDstAddress)
        settings.skipSrcAddress = Self.normalizedList(settings.skipSrcAddress)
        return settings
    }

    private var snifferDraftValidationMessage: String? {
        let settings = normalizedSnifferDraft
        if !SnifferValidator.isValidPortList(settings.httpPorts) {
            return "HTTP ports must be 1–65535."
        }
        if !SnifferValidator.isValidPortList(settings.tlsPorts) {
            return "TLS ports must be 1–65535."
        }
        if !SnifferValidator.isValidPortList(settings.quicPorts) {
            return "QUIC ports must be 1–65535."
        }
        if !settings.skipDomain.allSatisfy({ DNSValidator.isValidDomainWildcard($0) }) {
            return "Skip domain contains invalid wildcard."
        }
        if !settings.forceDomain.allSatisfy({ DNSValidator.isValidDomainWildcard($0) }) {
            return "Force domain contains invalid wildcard."
        }
        if !settings.skipDstAddress.allSatisfy({ DNSValidator.isValidCIDR($0) }) {
            return "Skip destination address must be valid CIDR."
        }
        if !settings.skipSrcAddress.allSatisfy({ DNSValidator.isValidCIDR($0) }) {
            return "Skip source address must be valid CIDR."
        }
        return nil
    }

    private func applySnifferDraft() {
        let settings = normalizedSnifferDraft
        updateSnifferDraft(settings)
        Task { await store.applySnifferSettings(settings) }
    }

    private func updateSnifferDraft(_ settings: SnifferSettings) {
        snifferDraft = settings
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

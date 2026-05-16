import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct SnifferView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void
    @State private var snifferDraft = SnifferSettings()
    @State private var httpPortsTextDraft = SnifferSettings().httpPorts.map(String.init).joined(separator: ",")
    @State private var tlsPortsTextDraft = SnifferSettings().tlsPorts.map(String.init).joined(separator: ",")
    @State private var quicPortsTextDraft = SnifferSettings().quicPorts.map(String.init).joined(separator: ",")
    @State private var skipDomainTextDraft = SnifferSettings().skipDomain.joined(separator: "\n")
    @State private var forceDomainTextDraft = SnifferSettings().forceDomain.joined(separator: "\n")
    @State private var skipDstAddressTextDraft = SnifferSettings().skipDstAddress.joined(separator: "\n")
    @State private var skipSrcAddressTextDraft = SnifferSettings().skipSrcAddress.joined(separator: "\n")

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

                Section("Ports") {
                    TextField("HTTP Ports", text: $httpPortsTextDraft)
                        .onChange(of: httpPortsTextDraft) { _, _ in
                            snifferDraft.httpPorts = SnifferValidator.parsePortString(httpPortsTextDraft)
                        }
                    TextField("TLS Ports", text: $tlsPortsTextDraft)
                        .onChange(of: tlsPortsTextDraft) { _, _ in
                            snifferDraft.tlsPorts = SnifferValidator.parsePortString(tlsPortsTextDraft)
                        }
                    TextField("QUIC Ports", text: $quicPortsTextDraft)
                        .onChange(of: quicPortsTextDraft) { _, _ in
                            snifferDraft.quicPorts = SnifferValidator.parsePortString(quicPortsTextDraft)
                        }
                }

                Section("Domain Filters") {
                    TextEditor(text: $skipDomainTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Skip Domain")
                        .onChange(of: skipDomainTextDraft) { _, _ in
                            snifferDraft.skipDomain = Self.lineList(from: skipDomainTextDraft)
                        }

                    TextEditor(text: $forceDomainTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Force Domain")
                        .onChange(of: forceDomainTextDraft) { _, _ in
                            snifferDraft.forceDomain = Self.lineList(from: forceDomainTextDraft)
                        }
                }

                Section("Address Filters") {
                    TextEditor(text: $skipDstAddressTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Skip Destination Address")
                        .onChange(of: skipDstAddressTextDraft) { _, _ in
                            snifferDraft.skipDstAddress = Self.lineList(from: skipDstAddressTextDraft)
                        }

                    TextEditor(text: $skipSrcAddressTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Skip Source Address")
                        .onChange(of: skipSrcAddressTextDraft) { _, _ in
                            snifferDraft.skipSrcAddress = Self.lineList(from: skipSrcAddressTextDraft)
                        }
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
        httpPortsTextDraft = settings.httpPorts.map(String.init).joined(separator: ",")
        tlsPortsTextDraft = settings.tlsPorts.map(String.init).joined(separator: ",")
        quicPortsTextDraft = settings.quicPorts.map(String.init).joined(separator: ",")
        skipDomainTextDraft = settings.skipDomain.joined(separator: "\n")
        forceDomainTextDraft = settings.forceDomain.joined(separator: "\n")
        skipDstAddressTextDraft = settings.skipDstAddress.joined(separator: "\n")
        skipSrcAddressTextDraft = settings.skipSrcAddress.joined(separator: "\n")
    }

    private static func lineList(from value: String) -> [String] {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}


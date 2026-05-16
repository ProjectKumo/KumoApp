import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct TunView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var isConfirmingServiceUninstall = false
    @State private var tunDraft = TunSettings()
    @State private var dnsHijackTextDraft = TunSettings().dnsHijack.joined(separator: ",")
    @State private var routeExcludeTextDraft = ""
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        KumoPage(title: "TUN") {
            Form {
                Section("Status") {
                    LabeledContent("Helper", value: helperState)
                    LabeledContent("TUN", value: store.tunStatus.isRunning ? "Running" : "Stopped")
                    if let message = store.serviceModeStatus.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Install / Repair Service") {
                            Task { await store.installServiceMode() }
                        }
                        .disabled(store.isLoading)
                        .help("Install or repair Kumo Helper with macOS administrator authorization.")
                        Button("Uninstall Service") {
                            isConfirmingServiceUninstall = true
                        }
                        .disabled(!store.serviceModeStatus.isInstalled || store.isLoading)
                    }
                }

                Section("Runtime") {
                    Toggle("Enable TUN", isOn: Binding {
                        currentTunSettings.isEnabled
                    } set: { isEnabled in
                        Task { await store.setTunEnabled(isEnabled) }
                    })
                    .disabled(store.isLoading)
                    if let lastError = store.tunStatus.lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Stack", selection: $tunDraft.stack) {
                        Text("Mixed").tag("mixed")
                        Text("gVisor").tag("gvisor")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Auto Route", isOn: $tunDraft.autoRoute)
                    Toggle("Auto Detect Interface", isOn: $tunDraft.autoDetectInterface)
                    Toggle("Strict Route", isOn: $tunDraft.strictRoute)
                    Toggle("ICMP Forwarding", isOn: icmpForwardingBinding)
                    TextField("MTU", value: $tunDraft.mtu, format: .number)
                } header: {
                    Text("Routing")
                } footer: {
                    Text("Routing changes are staged locally. Apply restarts the core when it is running so Mihomo reloads the generated TUN configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("DNS Hijack", text: dnsHijackTextBinding)
                } header: {
                    Text("DNS Hijack")
                } footer: {
                    Text("Enter DNS hijack values separated by commas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: routeExcludeTextBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Excluded CIDR ranges")
                } header: {
                    Text("Route Exclude")
                } footer: {
                    Text("Use one CIDR range per line, for example 100.64.0.0/10.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if let validationMessage = tunDraftValidationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button("Reset") {
                            updateTunDraft(currentTunSettings)
                        }
                        .disabled(!hasTunDraftChanges || store.isLoading)

                        Button("Apply") {
                            applyTunDraft()
                        }
                        .disabled(!canApplyTunDraft)
                    }
                } footer: {
                    Text("TUN requires Kumo Helper or a privileged Kumo process so Mihomo can create the utun interface. This path does not use macOS VPN configuration prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Profile") {
                    Button {
                        onNavigate(.profiles)
                    } label: {
                        Label("Open Profile YAML", systemImage: "doc.text")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task {
            store.refreshServiceModeStatus()
            store.refreshTunStatus()
            updateTunDraft(currentTunSettings)
        }
        .onChange(of: currentTunSettings) { _, newValue in
            if !hasTunDraftChanges {
                updateTunDraft(newValue)
            } else {
                tunDraft.isEnabled = newValue.isEnabled
            }
        }
        .confirmationDialog(
            "Uninstall Kumo Helper?",
            isPresented: $isConfirmingServiceUninstall,
            titleVisibility: .visible
        ) {
            Button("Uninstall Service", role: .destructive) {
                Task { await store.uninstallServiceMode() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the privileged helper used for TUN and protected system integration. TUN will not be manageable until the service is installed again.")
        }
    }

    private var helperState: String {
        if store.serviceModeStatus.canManageTun {
            return store.serviceModeStatus.isCurrentProcessPrivileged ? "Privileged Process" : "Running"
        }
        return store.serviceModeStatus.isInstalled ? "Installed, Not Running" : "Not Installed"
    }

    private var currentTunSettings: TunSettings {
        store.status.runtimeSettings?.tun ?? TunSettings()
    }

    private var normalizedTunDraft: TunSettings {
        normalizedTunSettings(tunDraft)
    }

    private var hasTunDraftChanges: Bool {
        comparableTunSettings(normalizedTunDraft) != comparableTunSettings(currentTunSettings)
    }

    private var canApplyTunDraft: Bool {
        hasTunDraftChanges && tunDraftValidationMessage == nil && !store.isLoading
    }

    private var tunDraftValidationMessage: String? {
        let settings = normalizedTunDraft
        if settings.dnsHijack.isEmpty {
            return "DNS Hijack needs at least one value."
        }
        if let invalidCIDR = settings.routeExcludeAddress.first(where: { !Self.isCIDR($0) }) {
            return "Route Exclude contains an invalid CIDR: \(invalidCIDR)"
        }
        return nil
    }

    private var icmpForwardingBinding: Binding<Bool> {
        Binding {
            !tunDraft.disableICMPForwarding
        } set: { value in
            tunDraft.disableICMPForwarding = !value
        }
    }

    private var dnsHijackTextBinding: Binding<String> {
        Binding {
            dnsHijackTextDraft
        } set: { value in
            dnsHijackTextDraft = value
            tunDraft.dnsHijack = Self.commaSeparatedList(from: value)
        }
    }

    private var routeExcludeTextBinding: Binding<String> {
        Binding {
            routeExcludeTextDraft
        } set: { value in
            routeExcludeTextDraft = value
            tunDraft.routeExcludeAddress = Self.lineList(from: value)
        }
    }

    private func applyTunDraft() {
        let settings = normalizedTunDraft
        updateTunDraft(settings)
        Task { await store.applyTunSettings(settings) }
    }

    private func updateTunDraft(_ settings: TunSettings) {
        let settings = normalizedTunSettings(settings)
        tunDraft = settings
        dnsHijackTextDraft = settings.dnsHijack.joined(separator: ",")
        routeExcludeTextDraft = settings.routeExcludeAddress.joined(separator: "\n")
    }

    private func normalizedTunSettings(_ settings: TunSettings) -> TunSettings {
        var settings = settings
        settings.isEnabled = currentTunSettings.isEnabled
        settings.stack = ["mixed", "gvisor", "system"].contains(settings.stack) ? settings.stack : "mixed"
        settings.mtu = max(576, min(9000, settings.mtu))
        settings.dnsHijack = Self.normalizedList(settings.dnsHijack)
        settings.routeExcludeAddress = Self.normalizedList(settings.routeExcludeAddress)
        return settings
    }

    private func comparableTunSettings(_ settings: TunSettings) -> TunSettings {
        var settings = normalizedTunSettings(settings)
        settings.isEnabled = false
        return settings
    }

    private static func commaSeparatedList(from text: String) -> [String] {
        normalizedList(text.components(separatedBy: ","))
    }

    private static func lineList(from text: String) -> [String] {
        normalizedList(text.components(separatedBy: .newlines))
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              let prefix = Int(parts[1]) else {
            return false
        }

        if parts[0].contains(":") {
            return (0...128).contains(prefix)
        }

        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, (0...32).contains(prefix) else {
            return false
        }
        return octets.allSatisfy { octet in
            guard let value = Int(octet) else { return false }
            return (0...255).contains(value)
        }
    }
}


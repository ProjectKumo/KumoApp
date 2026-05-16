import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct DNSView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void
    @State private var dnsDraft = DnsSettings()
    @State private var fakeIPFilterTextDraft = ""
    @State private var defaultNameserverTextDraft = ""
    @State private var nameserverTextDraft = ""
    @State private var proxyServerNameserverTextDraft = ""
    @State private var directNameserverTextDraft = ""
    @State private var fallbackTextDraft = ""
    @State private var fallbackFilterTextDraft = ""
    @State private var nameserverPolicyTextDraft = ""
    @State private var proxyServerNameserverPolicyTextDraft = ""
    @State private var hostsTextDraft = ""

    var body: some View {
        KumoPage(title: "DNS") {
            Form {
                Section("Status") {
                    Toggle("Enable DNS", isOn: Binding {
                        currentDnsSettings.isEnabled
                    } set: { isEnabled in
                        Task { await store.setDnsEnabled(isEnabled) }
                    })
                    .disabled(store.isLoading)
                }

                Section("Mode") {
                    Picker("Enhanced Mode", selection: $dnsDraft.enhancedMode) {
                        Text("Fake IP").tag("fake-ip")
                        Text("Redir Host").tag("redir-host")
                        Text("Normal").tag("normal")
                    }
                    .pickerStyle(.segmented)
                    Toggle("IPv6", isOn: $dnsDraft.ipv6)
                    Toggle("Use Hosts", isOn: $dnsDraft.useHosts)
                    Toggle("Use System Hosts", isOn: $dnsDraft.useSystemHosts)
                    Toggle("Respect Rules", isOn: $dnsDraft.respectRules)
                }

                Section("Advanced") {
                    TextField("Listen", text: $dnsDraft.listen)
                    TextField("IPv6 Timeout", value: $dnsDraft.ipv6Timeout, format: .number)
                    Toggle("Prefer HTTP/3", isOn: $dnsDraft.preferH3)
                    Picker("Fake IP Filter Mode", selection: $dnsDraft.fakeIPFilterMode) {
                        Text("None").tag("")
                        Text("Blacklist").tag("blacklist")
                        Text("Whitelist").tag("whitelist")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Direct Nameserver Follow Policy", isOn: $dnsDraft.directNameserverFollowPolicy)
                    Picker("Cache Algorithm", selection: $dnsDraft.cacheAlgorithm) {
                        Text("None").tag("")
                        Text("LRU").tag("lru")
                        Text("ARC").tag("arc")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Ranges") {
                    TextField("Fake IP Range", text: $dnsDraft.fakeIPRange)
                    TextField("Fake IP Range IPv6", text: $dnsDraft.fakeIPRange6)
                    TextEditor(text: $fakeIPFilterTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Fake IP Filter")
                        .onChange(of: fakeIPFilterTextDraft) { _, _ in
                            dnsDraft.fakeIPFilter = Self.lineList(from: fakeIPFilterTextDraft)
                        }
                }

                Section("Nameservers") {
                    TextEditor(text: $defaultNameserverTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .accessibilityLabel("Default Nameserver")
                        .onChange(of: defaultNameserverTextDraft) { _, _ in
                            dnsDraft.defaultNameserver = Self.lineList(from: defaultNameserverTextDraft)
                        }

                    TextEditor(text: $nameserverTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .accessibilityLabel("Nameserver")
                        .onChange(of: nameserverTextDraft) { _, _ in
                            dnsDraft.nameserver = Self.lineList(from: nameserverTextDraft)
                        }

                    TextEditor(text: $proxyServerNameserverTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .accessibilityLabel("Proxy Server Nameserver")
                        .onChange(of: proxyServerNameserverTextDraft) { _, _ in
                            dnsDraft.proxyServerNameserver = Self.lineList(from: proxyServerNameserverTextDraft)
                        }

                    TextEditor(text: $directNameserverTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .accessibilityLabel("Direct Nameserver")
                        .onChange(of: directNameserverTextDraft) { _, _ in
                            dnsDraft.directNameserver = Self.lineList(from: directNameserverTextDraft)
                        }
                }

                Section("Fallback") {
                    TextEditor(text: $fallbackTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .accessibilityLabel("Fallback Nameserver")
                        .onChange(of: fallbackTextDraft) { _, _ in
                            dnsDraft.fallback = Self.lineList(from: fallbackTextDraft)
                        }

                    TextEditor(text: $fallbackFilterTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .accessibilityLabel("Fallback Filter")
                        .onChange(of: fallbackFilterTextDraft) { _, _ in
                            dnsDraft.fallbackFilter = Self.fallbackFilterDict(from: fallbackFilterTextDraft)
                        }
                }

                Section("Policy") {
                    TextEditor(text: $nameserverPolicyTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Nameserver Policy")
                        .onChange(of: nameserverPolicyTextDraft) { _, _ in
                            dnsDraft.nameserverPolicy = Self.policyValueDict(from: nameserverPolicyTextDraft)
                        }

                    TextEditor(text: $proxyServerNameserverPolicyTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Proxy Server Nameserver Policy")
                        .onChange(of: proxyServerNameserverPolicyTextDraft) { _, _ in
                            dnsDraft.proxyServerNameserverPolicy = Self.policyValueDict(from: proxyServerNameserverPolicyTextDraft)
                        }
                }

                Section("Hosts") {
                    TextEditor(text: $hostsTextDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Hosts")
                        .onChange(of: hostsTextDraft) { _, _ in
                            dnsDraft.hosts = Self.policyValueDict(from: hostsTextDraft)
                        }
                }

                Section {
                    if let validationMessage = dnsDraftValidationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button("Reset") {
                            updateDnsDraft(currentDnsSettings)
                        }
                        .disabled(!hasDnsDraftChanges || store.isLoading)

                        Button("Apply") {
                            applyDnsDraft()
                        }
                        .disabled(!canApplyDnsDraft)
                    }
                } footer: {
                    Text("DNS changes are staged locally. Apply restarts the core when it is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .task {
            updateDnsDraft(currentDnsSettings)
        }
        .onChange(of: currentDnsSettings) { _, newValue in
            if !hasDnsDraftChanges {
                updateDnsDraft(newValue)
            } else {
                dnsDraft.isEnabled = newValue.isEnabled
            }
        }
    }

    private var currentDnsSettings: DnsSettings {
        store.status.runtimeSettings?.dns ?? DnsSettings()
    }

    private var hasDnsDraftChanges: Bool {
        normalizedDnsDraft != currentDnsSettings
    }

    private var canApplyDnsDraft: Bool {
        hasDnsDraftChanges && dnsDraftValidationMessage == nil && !store.isLoading
    }

    private var normalizedDnsDraft: DnsSettings {
        var settings = dnsDraft
        settings.enhancedMode = ["fake-ip", "redir-host", "normal"].contains(settings.enhancedMode)
            ? settings.enhancedMode
            : "fake-ip"
        settings.listen = settings.listen.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.fakeIPRange = settings.fakeIPRange.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.fakeIPRange6 = settings.fakeIPRange6.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.fakeIPFilter = Self.normalizedList(settings.fakeIPFilter)
        settings.fakeIPFilterMode = settings.fakeIPFilterMode.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultNameserver = Self.normalizedList(settings.defaultNameserver)
        settings.nameserver = Self.normalizedList(settings.nameserver)
        settings.fallback = Self.normalizedList(settings.fallback)
        settings.proxyServerNameserver = Self.normalizedList(settings.proxyServerNameserver)
        settings.directNameserver = Self.normalizedList(settings.directNameserver)
        settings.fallbackFilter = settings.fallbackFilter.mapValues { value in
            switch value {
            case .bool(let b):
                return .bool(b)
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(Self.normalizedList(arr))
            }
        }
        settings.nameserverPolicy = settings.nameserverPolicy.mapValues { value in
            switch value {
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(Self.normalizedList(arr))
            }
        }
        settings.proxyServerNameserverPolicy = settings.proxyServerNameserverPolicy.mapValues { value in
            switch value {
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(Self.normalizedList(arr))
            }
        }
        settings.hosts = settings.hosts.mapValues { value in
            switch value {
            case .single(let s):
                return .single(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case .multiple(let arr):
                return .multiple(Self.normalizedList(arr))
            }
        }
        settings.cacheAlgorithm = settings.cacheAlgorithm.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings
    }

    private var dnsDraftValidationMessage: String? {
        let settings = normalizedDnsDraft
        if settings.isEnabled {
            if settings.nameserver.isEmpty {
                return "Nameserver needs at least one value when DNS is enabled."
            }
            if settings.enhancedMode == "fake-ip", !Self.isCIDR(settings.fakeIPRange) {
                return "Fake IP Range must use CIDR notation."
            }
        }
        if !settings.listen.isEmpty, !DNSValidator.isValidListenAddress(settings.listen) {
            return "Listen address format is invalid. Use :port or host:port."
        }
        if !DNSValidator.isValidFakeIPFilterMode(settings.fakeIPFilterMode) {
            return "Fake IP Filter Mode must be blacklist or whitelist."
        }
        if !DNSValidator.isValidCacheAlgorithm(settings.cacheAlgorithm) {
            return "Cache Algorithm must be lru or arc."
        }
        return nil
    }

    private func applyDnsDraft() {
        let settings = normalizedDnsDraft
        updateDnsDraft(settings)
        Task { await store.applyDnsSettings(settings) }
    }

    private func updateDnsDraft(_ settings: DnsSettings) {
        dnsDraft = settings
        fakeIPFilterTextDraft = settings.fakeIPFilter.joined(separator: "\n")
        defaultNameserverTextDraft = settings.defaultNameserver.joined(separator: "\n")
        nameserverTextDraft = settings.nameserver.joined(separator: "\n")
        proxyServerNameserverTextDraft = settings.proxyServerNameserver.joined(separator: "\n")
        directNameserverTextDraft = settings.directNameserver.joined(separator: "\n")
        fallbackTextDraft = settings.fallback.joined(separator: "\n")
        fallbackFilterTextDraft = settings.fallbackFilter.map { entry in
            switch entry.value {
            case .bool(let b): return "\(entry.key): \(b)"
            case .single(let s): return "\(entry.key): \(s)"
            case .multiple(let arr): return "\(entry.key): \(arr.joined(separator: ", "))"
            }
        }.joined(separator: "\n")
        nameserverPolicyTextDraft = settings.nameserverPolicy.map { "\($0.key): \($0.value.strings.joined(separator: ", "))" }.joined(separator: "\n")
        proxyServerNameserverPolicyTextDraft = settings.proxyServerNameserverPolicy.map { "\($0.key): \($0.value.strings.joined(separator: ", "))" }.joined(separator: "\n")
        hostsTextDraft = settings.hosts.map { "\($0.key): \($0.value.strings.joined(separator: ", "))" }.joined(separator: "\n")
    }

    private static func lineList(from text: String) -> [String] {
        normalizedList(text.components(separatedBy: .newlines))
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func policyValueDict(from text: String) -> [String: PolicyValue] {
        var result: [String: PolicyValue] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    result[key] = .single(value)
                }
            }
        }
        return result
    }

    private static func fallbackFilterDict(from text: String) -> [String: FallbackFilterValue] {
        var result: [String: FallbackFilterValue] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                if value == "true" {
                    result[key] = .bool(true)
                } else if value == "false" {
                    result[key] = .bool(false)
                } else if value.contains(",") {
                    let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    result[key] = .multiple(parts)
                } else {
                    result[key] = .single(value)
                }
            }
        }
        return result
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


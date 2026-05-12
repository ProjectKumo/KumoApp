import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

private struct ControllerSecretField: View {
    let currentSecret: String
    let commit: (String) -> Void
    @State private var draft: String = ""
    @State private var hasChanges = false

    var body: some View {
        HStack {
            SecureField("Controller Secret", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft) { _, _ in
                    hasChanges = draft != currentSecret
                }
                .onSubmit { applyIfNeeded() }
            Button("Apply") {
                applyIfNeeded()
            }
            .disabled(!hasChanges)
        }
        .onAppear {
            draft = currentSecret
            hasChanges = false
        }
        .onChange(of: currentSecret) { _, newValue in
            // Sync only when the user has not typed pending changes,
            // otherwise the in-progress edit would be clobbered by store
            // updates triggered elsewhere.
            if !hasChanges {
                draft = newValue
            }
        }
    }

    private func applyIfNeeded() {
        guard hasChanges else { return }
        commit(draft)
        hasChanges = false
    }
}

private struct DebouncedTextEditor: View {
    let value: String
    let commit: (String) -> Void
    let minHeight: CGFloat
    let milliseconds: Int
    @State private var draft: String = ""
    @State private var debounceTask: Task<Void, Never>?

    init(value: String, minHeight: CGFloat = 120, milliseconds: Int = 500, commit: @escaping (String) -> Void) {
        self.value = value
        self.commit = commit
        self.minHeight = minHeight
        self.milliseconds = milliseconds
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: minHeight)
            .onAppear {
                if draft.isEmpty {
                    draft = value
                }
            }
            .onChange(of: draft) { _, newValue in
                debounceTask?.cancel()
                let captured = newValue
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(milliseconds))
                    guard !Task.isCancelled, captured != value else { return }
                    commit(captured)
                }
            }
            .onChange(of: value) { _, newValue in
                if debounceTask == nil && newValue != draft {
                    draft = newValue
                }
            }
    }
}

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

struct DNSView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        ProfileBackedConfigPage(
            title: "DNS",
            systemImage: "globe",
            rows: [("Managed", store.coreConfiguration.dnsEnabled ? "On" : "Off")],
            onNavigate: onNavigate
        )
    }
}

struct TunView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var isConfirmingServiceUninstall = false
    @State private var tunDraft = TunSettings()
    @State private var dnsHijackTextDraft = TunSettings().dnsHijack.joined(separator: ",")
    @State private var routeExcludeTextDraft = ""
    @State private var nameserversTextDraft = TunSettings().nameservers.joined(separator: "\n")
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
                    Toggle("Enable DNS", isOn: $tunDraft.dnsEnabled)
                    Picker("Enhanced Mode", selection: $tunDraft.dnsEnhancedMode) {
                        Text("Fake IP").tag("fake-ip")
                        Text("Redir Host").tag("redir-host")
                        Text("Normal").tag("normal")
                    }
                    .pickerStyle(.segmented)
                    TextField("Fake IP Range", text: $tunDraft.fakeIPRange)
                    TextField("DNS Hijack", text: dnsHijackTextBinding)
                    TextEditor(text: nameserversTextBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 86)
                        .accessibilityLabel("Nameservers")
                } header: {
                    Text("DNS")
                } footer: {
                    Text("Enter DNS hijack values separated by commas. Enter nameservers one per line.")
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
        if settings.dnsEnabled, settings.nameservers.isEmpty {
            return "Nameservers need at least one value when DNS is enabled."
        }
        if settings.dnsEnabled, settings.dnsEnhancedMode == "fake-ip", !Self.isCIDR(settings.fakeIPRange) {
            return "Fake IP Range must use CIDR notation."
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

    private var nameserversTextBinding: Binding<String> {
        Binding {
            nameserversTextDraft
        } set: { value in
            nameserversTextDraft = value
            tunDraft.nameservers = Self.lineList(from: value)
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
        nameserversTextDraft = settings.nameservers.joined(separator: "\n")
    }

    private func normalizedTunSettings(_ settings: TunSettings) -> TunSettings {
        var settings = settings
        settings.isEnabled = currentTunSettings.isEnabled
        settings.stack = ["mixed", "gvisor", "system"].contains(settings.stack) ? settings.stack : "mixed"
        settings.dnsEnhancedMode = ["fake-ip", "redir-host", "normal"].contains(settings.dnsEnhancedMode)
            ? settings.dnsEnhancedMode
            : "fake-ip"
        settings.mtu = max(576, min(9000, settings.mtu))
        settings.fakeIPRange = settings.fakeIPRange.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.dnsHijack = Self.normalizedList(settings.dnsHijack)
        settings.routeExcludeAddress = Self.normalizedList(settings.routeExcludeAddress)
        settings.nameservers = Self.normalizedList(settings.nameservers)
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

struct SnifferView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        ProfileBackedConfigPage(
            title: "Sniffer",
            systemImage: "scope",
            rows: [("Enabled", store.coreConfiguration.snifferEnabled ? "On" : "Off")],
            onNavigate: onNavigate
        )
    }
}

struct ResourcesView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        KumoPage(title: "Resources") {
            Form {
                Section("Geo Data") {
                    TextField("GeoIP DAT", text: geoIPURLBinding)
                    TextField("GeoSite", text: geoSiteURLBinding)
                    TextField("MMDB", text: mmdbURLBinding)
                    TextField("ASN", text: asnURLBinding)
                    Toggle("GeoIP DAT Mode", isOn: geoDatModeBinding)
                    Toggle("Auto Update", isOn: geoAutoUpdateBinding)
                    TextField("Update Interval (hours)", value: geoUpdateIntervalBinding, format: .number)
                    Button("Update Geo Data") {
                        Task { await store.upgradeGeoData() }
                    }
                    .disabled(store.status.state != .running || store.isLoading)
                }

                Section("Proxy Providers") {
                    if store.proxyProviders.isEmpty {
                        Text(store.status.state == .running ? "No proxy providers reported by Mihomo." : "Start Kumo to inspect providers.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Update All Providers") {
                            Task { await store.updateAllProviders() }
                        }
                        ForEach(store.proxyProviders) { provider in
                            ProviderRow(title: provider.name, detail: "\(provider.vehicleType) · \(provider.proxyCount) proxies") {
                                Button("Update") {
                                    Task { await store.updateProxyProvider(provider) }
                                }
                            }
                        }
                    }
                }

                Section("Rule Providers") {
                    if store.ruleProviders.isEmpty {
                        Text(store.status.state == .running ? "No rule providers reported by Mihomo." : "Start Kumo to inspect providers.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.ruleProviders) { provider in
                            ProviderRow(title: provider.name, detail: "\(provider.vehicleType)::\(provider.behavior) · \(provider.ruleCount) rules") {
                                Button("Update") {
                                    Task { await store.updateRuleProvider(provider) }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task {
            await store.loadResources()
        }
    }

    private var runtimeSettings: CoreRuntimeSettings {
        store.status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: store.status.proxyPorts.mixedPort)
    }

    private func updateGeoData(_ edit: (inout GeoDataSettings) -> Void) {
        var settings = runtimeSettings
        edit(&settings.geoData)
        Task { await store.updateRuntimeSettings(settings) }
    }

    private var geoIPURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.geoIPURL } set: { value in updateGeoData { $0.geoIPURL = value } }
    }

    private var geoSiteURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.geoSiteURL } set: { value in updateGeoData { $0.geoSiteURL = value } }
    }

    private var mmdbURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.mmdbURL } set: { value in updateGeoData { $0.mmdbURL = value } }
    }

    private var asnURLBinding: Binding<String> {
        Binding { runtimeSettings.geoData.asnURL } set: { value in updateGeoData { $0.asnURL = value } }
    }

    private var geoDatModeBinding: Binding<Bool> {
        Binding { runtimeSettings.geoData.usesDatMode } set: { value in updateGeoData { $0.usesDatMode = value } }
    }

    private var geoAutoUpdateBinding: Binding<Bool> {
        Binding { runtimeSettings.geoData.autoUpdate } set: { value in updateGeoData { $0.autoUpdate = value } }
    }

    private var geoUpdateIntervalBinding: Binding<Int> {
        Binding { runtimeSettings.geoData.updateIntervalHours } set: { value in updateGeoData { $0.updateIntervalHours = max(1, value) } }
    }
}

struct OverridesView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var remoteURL = ""
    @State private var isGlobal = false
    @State private var format: OverrideFormat = .yaml
    @State private var isImportingFile = false
    @State private var editingDraft: OverrideDraft?
    @State private var deletingOverride: OverrideItem?
    @State private var newDraft: NewOverrideDraft?

    var body: some View {
        KumoPage(title: "Overrides") {
            VStack(alignment: .leading, spacing: 12) {
                importControls

                if store.overrides.isEmpty {
                    KumoEmptyState(
                        title: "No Overrides",
                        systemImage: "slider.horizontal.3",
                        message: "Import or create a YAML override to modify the runtime profile."
                    ) {
                        Button("Choose File") {
                            isImportingFile = true
                        }
                    }
                } else {
                    List(store.overrides) { item in
                        OverrideRow(
                            item: item,
                            onEdit: { openEditor(for: item) },
                            onDelete: { deletingOverride = item }
                        )
                    }
                    .scrollEdgeEffectStyleIfAvailable()
                }
            }
        }
        .task {
            store.refreshOverrides()
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let fileFormat: OverrideFormat = url.pathExtension.localizedCaseInsensitiveContains("js") ? .javascript : .yaml
                store.addLocalOverride(name: url.deletingPathExtension().lastPathComponent, format: fileFormat, content: content, isGlobal: isGlobal)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $editingDraft) { draft in
            OverrideEditorSheet(draft: draft) { editedDraft in
                store.updateOverride(editedDraft.item, content: editedDraft.content)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .sheet(item: $newDraft) { draft in
            NewOverrideSheet(draft: draft) { editedDraft in
                let template = editedDraft.format == .yaml ? "# Kumo YAML override\n" : "// Kumo JavaScript override\n"
                store.addLocalOverride(
                    name: editedDraft.name,
                    format: editedDraft.format,
                    content: template,
                    isGlobal: editedDraft.isGlobal
                )
                newDraft = nil
            } onCancel: {
                newDraft = nil
            }
        }
        .confirmationDialog(
            "Delete Override?",
            isPresented: Binding {
                deletingOverride != nil
            } set: { isPresented in
                if !isPresented {
                    deletingOverride = nil
                }
            },
            presenting: deletingOverride
        ) { item in
            Button("Delete \(item.name)", role: .destructive) {
                store.deleteOverride(item)
                deletingOverride = nil
            }
            Button("Cancel", role: .cancel) {
                deletingOverride = nil
            }
        } message: { _ in
            Text("This removes the local override file and metadata.")
        }
    }

    private var importControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                remoteOverrideURLField
                overrideOptions
                overrideActionGroup
            }

            VStack(alignment: .leading, spacing: 8) {
                remoteOverrideURLField
                HStack(spacing: 8) {
                    overrideOptions
                    Spacer()
                    overrideActionGroup
                }
            }
        }
    }

    private var remoteOverrideURLField: some View {
        TextField("Remote override URL", text: $remoteURL)
            .textFieldStyle(.roundedBorder)
    }

    private var overrideOptions: some View {
        HStack(spacing: 8) {
            Picker("Format", selection: $format) {
                Text("YAML").tag(OverrideFormat.yaml)
                Text("JavaScript").tag(OverrideFormat.javascript)
            }
            .frame(width: 140)

            Toggle("Global", isOn: $isGlobal)
                .toggleStyle(.checkbox)
                .fixedSize()
        }
    }

    private var overrideActionGroup: some View {
        HStack(spacing: 8) {
            Button("Import URL") {
                Task {
                    await store.addRemoteOverride(urlString: remoteURL, format: format, isGlobal: isGlobal)
                    if store.errorMessage == nil {
                        remoteURL = ""
                    }
                }
            }
            .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)

            Button("Import File…") {
                isImportingFile = true
            }

            Button("New…") {
                newDraft = NewOverrideDraft(isGlobal: isGlobal)
            }
        }
    }

    private func openEditor(for item: OverrideItem) {
        guard let content = store.overrideContent(id: item.id) else {
            return
        }
        editingDraft = OverrideDraft(item: item, content: content)
    }
}

private struct OverrideRow: View {
    let item: OverrideItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.format == .yaml ? "doc.text" : "curlybraces")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text("\(item.kind.rawValue.capitalized) · \(item.format.rawValue.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isGlobal {
                Text("Global")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Edit") { onEdit() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .contextMenu {
                Button("Edit") { onEdit() }
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

private struct NewOverrideDraft: Identifiable {
    let id = UUID()
    var name: String = "New Override"
    var format: OverrideFormat = .yaml
    var isGlobal: Bool

    init(isGlobal: Bool) {
        self.isGlobal = isGlobal
    }
}

private struct NewOverrideSheet: View {
    @State private var draft: NewOverrideDraft
    let onCreate: (NewOverrideDraft) -> Void
    let onCancel: () -> Void

    init(draft: NewOverrideDraft, onCreate: @escaping (NewOverrideDraft) -> Void, onCancel: @escaping () -> Void) {
        self._draft = State(initialValue: draft)
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Override")
                .font(.title2.weight(.semibold))
                .padding(.horizontal)
                .padding(.top)

            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Format", selection: $draft.format) {
                        Text("YAML").tag(OverrideFormat.yaml)
                        Text("JavaScript").tag(OverrideFormat.javascript)
                    }
                    Toggle("Global Override", isOn: $draft.isGlobal)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Button("Create") {
                    onCreate(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 420)
    }
}

private struct OverrideDraft: Identifiable {
    var item: OverrideItem
    var content: String

    var id: String { item.id }
}

private struct OverrideEditorSheet: View {
    @State private var draft: OverrideDraft
    let onSave: (OverrideDraft) -> Void
    let onCancel: () -> Void

    init(draft: OverrideDraft, onSave: @escaping (OverrideDraft) -> Void, onCancel: @escaping () -> Void) {
        self._draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Info") {
                    TextField("Name", text: $draft.item.name)
                    Toggle("Global Override", isOn: $draft.item.isGlobal)
                    LabeledContent("Format", value: draft.item.format.rawValue.uppercased())
                    if let remoteURL = draft.item.remoteURL {
                        LabeledContent("Remote URL", value: remoteURL.absoluteString)
                    }
                }

                Section("Content") {
                    TextEditor(text: $draft.content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 360)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Button("Save") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 640, minHeight: 560)
    }
}

private struct ProviderRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

private struct ProfileBackedConfigPage: View {
    let title: String
    let systemImage: String
    let rows: [(String, String)]
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        KumoPage(title: title) {
            Form {
                Section("Status") {
                    ForEach(rows, id: \.0) { row in
                        LabeledContent(row.0, value: row.1)
                    }
                }

                Section {
                    Button {
                        onNavigate(.profiles)
                    } label: {
                        Label("Edit in Profile YAML", systemImage: systemImage)
                    }
                } footer: {
                    Text("\(title) is configured in the active profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

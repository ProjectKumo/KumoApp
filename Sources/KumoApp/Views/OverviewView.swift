import SwiftUI
import KumoCoreKit

struct OverviewView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    init(onNavigate: @escaping (SidebarDestination) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    private var uploadSpeed: Int {
        store.trafficSnapshot.uploadSpeed
    }

    private var downloadSpeed: Int {
        store.trafficSnapshot.downloadSpeed
    }

    var body: some View {
        KumoPage(title: "Kumo") {
            VStack(alignment: .leading, spacing: 18) {
                statusMenuRow

                metricsGrid

                if store.status.state == .running, store.proxyGroups.isEmpty {
                    KumoInlineState(
                        title: "No Proxy Groups",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        message: "Import a profile with proxy groups."
                    ) {}
                    .padding(.top, 8)
                } else if !store.proxyGroups.isEmpty {
                    proxyGroupStatusSection
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var proxyGroupStatusSection: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                proxyGroupStatusCard
            }
        } else {
            proxyGroupStatusCard
        }
    }

    private var proxyGroupStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("Current Selections", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                if store.proxyGroups.count > 4 {
                    Button("View all") {
                        onNavigate(.proxies)
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .accessibilityHint("Open the Proxies page")
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(store.proxyGroups.prefix(4).enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 34)
                    }
                    ProxyGroupStatusRow(group: group, onNavigate: onNavigate)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 18)
    }

    @ViewBuilder
    private var metricsGrid: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                metricsGridContent
            }
        } else {
            metricsGridContent
        }
    }

    private var metricsGridContent: some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    connectionsMetricCard
                    trafficMetricCard
                }

                HStack(spacing: 12) {
                    proxyGroupsMetricCard
                    systemProxyMetricCard
                }

                controllerMetricCard
            }
            .frame(minWidth: 560, maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                connectionsMetricCard
                trafficMetricCard
                proxyGroupsMetricCard
                systemProxyMetricCard
                controllerMetricCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectionsMetricCard: some View {
        NetworkMetricCard(
            title: "Connections",
            value: "\(store.connections.count)",
            secondaryValue: nil,
            detail: store.status.state == .running ? "Active now" : "Core stopped",
            systemImage: "network",
            actionTitle: "Open Connections"
        ) {
            onNavigate(.connections)
        }
        .contextMenu {
            Button("Refresh Connections") {
                Task { await store.loadInspectData() }
            }
            Button("Open Connections") {
                onNavigate(.connections)
            }
        }
    }

    private var trafficMetricCard: some View {
        NetworkMetricCard(
            title: "Traffic",
            value: "↑ \(uploadSpeed.kumoByteCount)/s",
            secondaryValue: "↓ \(downloadSpeed.kumoByteCount)/s",
            detail: nil,
            systemImage: "speedometer",
            actionTitle: "Inspect Traffic"
        ) {
            onNavigate(.connections)
        }
        .contextMenu {
            Button("Refresh Traffic") {
                Task { await store.loadInspectData() }
            }
            Button("Open Connections") {
                onNavigate(.connections)
            }
        }
    }

    private var proxyGroupsMetricCard: some View {
        NetworkMetricCard(
            title: "Proxy Groups",
            value: "\(store.proxyGroups.count)",
            secondaryValue: nil,
            detail: nil,
            systemImage: "point.3.connected.trianglepath.dotted",
            actionTitle: "Open Proxies"
        ) {
            onNavigate(.proxies)
        }
        .contextMenu {
            Button("Refresh Proxy Groups") {
                Task { await store.loadProxyGroups() }
            }
            Button("Open Proxies") {
                onNavigate(.proxies)
            }
        }
    }

    private var systemProxyMetricCard: some View {
        NetworkMetricCard(
            title: "System Proxy",
            value: store.status.systemProxyEnabled ? "On" : "Off",
            secondaryValue: nil,
            detail: "\(store.status.endpoint.host):\(store.status.proxyPorts.mixedPort)",
            systemImage: "switch.2",
            actionTitle: "Configure System Proxy"
        ) {
            onNavigate(.systemProxy)
        }
        .contextMenu {
            Button(store.status.systemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy") {
                store.setSystemProxyEnabled(!store.status.systemProxyEnabled)
            }
            .disabled(store.status.state != .running && !store.status.systemProxyEnabled)
            Button("Open System Proxy Settings") {
                onNavigate(.systemProxy)
            }
        }
    }

    private var controllerMetricCard: some View {
        NetworkMetricCard(
            title: "Controller",
            value: "\(store.status.endpoint.port)",
            secondaryValue: nil,
            detail: store.status.endpoint.host,
            systemImage: "slider.horizontal.2.square",
            actionTitle: "Open Core Settings"
        ) {
            onNavigate(.core)
        }
        .contextMenu {
            Button("Refresh Controller") {
                Task { await store.loadCoreConfiguration() }
            }
            Button("Open Core Settings") {
                onNavigate(.core)
            }
        }
    }

    @ViewBuilder
    private var statusMenuRow: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                statusMenuContent
            }
        } else {
            statusMenuContent
        }
    }

    private var statusMenuContent: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                StatusMenuPill(
                    title: "Core",
                    value: store.status.state.rawValue.capitalized,
                    systemImage: store.status.state == .running ? "checkmark.circle.fill" : "pause.circle"
                ) {
                    Button("Refresh Status") {
                        store.refreshStatus()
                    }

                    Button("Scan Core Again") {
                        store.refreshCoreCandidates()
                    }

                    if !store.coreCandidates.isEmpty {
                        Divider()
                        ForEach(store.coreCandidates) { candidate in
                            Button {
                                store.setCorePath(candidate.path)
                            } label: {
                                Label(candidate.name, systemImage: store.status.corePath == candidate.path ? "checkmark" : "cpu")
                            }
                        }
                    }
                }

                StatusMenuPill(
                    title: "Profile",
                    value: store.currentProfile?.name ?? "Default",
                    systemImage: "rectangle.stack"
                ) {
                    if store.profiles.isEmpty {
                        Text("No profiles")
                    } else {
                        ForEach(store.profiles) { profile in
                            Button {
                                Task { await store.selectProfile(profile) }
                            } label: {
                                Label(profile.name, systemImage: profile.isCurrent ? "checkmark" : "rectangle.stack")
                            }
                            .disabled(profile.isCurrent || store.isLoading)
                        }
                    }
                }

                StatusMenuPill(
                    title: "Mode",
                    value: store.status.mode.displayName,
                    systemImage: "arrow.triangle.branch"
                ) {
                    ForEach(OutboundMode.allCases, id: \.self) { mode in
                        Button {
                            Task { await store.setMode(mode) }
                        } label: {
                            Label(mode.displayName, systemImage: store.status.mode == mode ? "checkmark" : "circle")
                        }
                        .disabled(store.status.mode == mode || store.isLoading || store.isSwitchingMode)
                    }
                }

                StatusMenuPill(
                    title: "System Proxy",
                    value: store.status.systemProxyEnabled ? "On" : "Off",
                    systemImage: "switch.2"
                ) {
                    Button(store.status.systemProxyEnabled ? "Disable System Proxy" : "Enable System Proxy") {
                        store.setSystemProxyEnabled(!store.status.systemProxyEnabled)
                    }
                    .disabled(store.status.state != .running && !store.status.systemProxyEnabled)
                }

                StatusMenuPill(
                    title: "TUN",
                    value: store.tunStatus.isEnabled ? "On" : "Off",
                    systemImage: store.tunStatus.isEnabled ? "lock.shield.fill" : "lock.shield"
                ) {
                    Button(store.tunStatus.isEnabled ? "Disable TUN" : "Enable TUN") {
                        Task { await store.setTunEnabled(!store.tunStatus.isEnabled) }
                    }
                    .disabled(store.isLoading)

                    Button("Open TUN Settings") {
                        onNavigate(.tun)
                    }

                    if store.tunStatus.requiresService {
                        Divider()
                        Button("Install / Repair Service") {
                            Task { await store.installServiceMode() }
                        }
                        .disabled(store.isLoading)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

private struct StatusMenuPill<MenuContent: View>: View {
    let title: String
    let value: String
    let systemImage: String?
    @ViewBuilder let menuContent: MenuContent

    var body: some View {
        Menu {
            menuContent
        } label: {
            StatusPill(
                title: title,
                value: value,
                systemImage: systemImage,
                showsMenuIndicator: true,
                showsSurface: false
            )
        }
        .menuIndicator(.hidden)
        .kumoGlassMenuButton()
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct NetworkMetricCard: View {
    let title: String
    let value: String
    let secondaryValue: String?
    let detail: String?
    let systemImage: String
    let actionTitle: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())

                if let secondaryValue {
                    Text(secondaryValue)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .contentShape(.rect(cornerRadius: 14))
            .kumoInteractiveGlass(cornerRadius: 14, tint: Color.accentColor.opacity(isHovered ? 0.12 : 0))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilitySummary)
        .accessibilityValue(detail ?? "")
        .accessibilityHint(actionTitle)
        .help(actionTitle)
    }

    private var accessibilitySummary: String {
        if let secondaryValue {
            return "\(title): \(value), \(secondaryValue)"
        }
        return "\(title): \(value)"
    }
}

private struct ProxyGroupStatusRow: View {
    @Environment(KumoAppStore.self) private var store
    let group: ProxyGroup
    let onNavigate: (SidebarDestination) -> Void
    private let maxMenuProxyCount = 12

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(group.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 16)

            selectionMenu
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), selected \(group.selectedProxyName ?? "no proxy")")
        .accessibilityHint("Opens a menu to switch the selected proxy.")
    }

    @ViewBuilder
    private var selectionMenu: some View {
        Menu {
            if group.proxies.isEmpty {
                Text("No proxies")
            } else {
                Button {
                    Task { await store.testDelay(for: group) }
                } label: {
                    Label("Test Delay", systemImage: "speedometer")
                }
                .disabled(store.isTestingDelay)

                Divider()

                ForEach(Array(group.proxies.prefix(maxMenuProxyCount))) { proxy in
                    Button {
                        Task { await store.selectProxy(group: group, proxy: proxy) }
                    } label: {
                        Label(
                            proxyMenuTitle(for: proxy),
                            systemImage: group.selectedProxyName == proxy.name ? "checkmark" : "circle"
                        )
                    }
                    .disabled(group.selectedProxyName == proxy.name || store.isLoading)
                }

                if group.proxies.count > maxMenuProxyCount {
                    Divider()
                    Button("Open Proxies…") {
                        onNavigate(.proxies)
                    }
                }
            }
        } label: {
            selectionLabel
        }
        .menuIndicator(.hidden)
        .kumoGlassMenuButton(cornerRadius: 12)
        .disabled(group.proxies.isEmpty)
        .help("Switch proxy for \(group.name)")
    }

    private var selectionLabel: some View {
        Text(group.selectedProxyName ?? "No selection")
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(group.selectedProxyName == nil ? .secondary : .primary)
    }

    private func proxyMenuTitle(for proxy: ProxyNode) -> String {
        guard let delay = proxy.delay, delay > 0 else {
            return proxy.name
        }
        return "\(proxy.name) — \(delay) ms"
    }
}

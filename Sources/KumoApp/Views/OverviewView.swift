import SwiftUI
import KumoCoreKit

struct OverviewView: View {
    @Environment(KumoAppStore.self) private var store

    private var totalUpload: Int {
        store.connections.reduce(0) { $0 + $1.upload }
    }

    private var totalDownload: Int {
        store.connections.reduce(0) { $0 + $1.download }
    }

    private var uploadSpeed: Int {
        store.connections.reduce(0) { $0 + $1.uploadSpeed }
    }

    private var downloadSpeed: Int {
        store.connections.reduce(0) { $0 + $1.downloadSpeed }
    }

    var body: some View {
        KumoPage(title: "Kumo") {
            VStack(alignment: .leading, spacing: 18) {
                statusMenuRow

                metricsGrid

                if store.proxyGroups.isEmpty {
                    KumoInlineState(
                        title: store.status.state == .running ? "No Proxy Groups" : "Core Stopped",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        message: store.status.state == .running
                            ? "Import a profile with proxy groups."
                            : "Use the toolbar controls to start Kumo."
                    ) {}
                    .padding(.top, 8)
                } else {
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
            Label("Current Selections", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(store.proxyGroups.prefix(4).enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 34)
                    }
                    ProxyGroupStatusRow(group: group)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
            NetworkMetricCard(
                title: "Connections",
                value: "\(store.connections.count)",
                detail: store.status.state == .running ? "Active now" : "Core stopped",
                systemImage: "network"
            )

            NetworkMetricCard(
                title: "Throughput",
                value: "↑ \(uploadSpeed.kumoByteCount)/s",
                detail: "↓ \(downloadSpeed.kumoByteCount)/s",
                systemImage: "speedometer"
            )

            NetworkMetricCard(
                title: "Traffic",
                value: "↑ \(totalUpload.kumoByteCount)",
                detail: "↓ \(totalDownload.kumoByteCount)",
                systemImage: "arrow.up.arrow.down"
            )

            NetworkMetricCard(
                title: "Proxy Groups",
                value: "\(store.proxyGroups.count)",
                detail: nil,
                systemImage: "point.3.connected.trianglepath.dotted"
            )

            NetworkMetricCard(
                title: "System Proxy",
                value: store.status.systemProxyEnabled ? "On" : "Off",
                detail: "\(store.status.endpoint.host):\(store.status.proxyPorts.mixedPort)",
                systemImage: "switch.2"
            )

            NetworkMetricCard(
                title: "Controller",
                value: "\(store.status.endpoint.port)",
                detail: store.status.endpoint.host,
                systemImage: "slider.horizontal.2.square"
            )
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
                    .disabled(store.status.mode == mode || store.isLoading)
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
        }
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
        .kumoGlassMenuButton()
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct NetworkMetricCard: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .kumoGlassCard(cornerRadius: 14)
    }
}

private struct ProxyGroupStatusRow: View {
    let group: ProxyGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Text(group.selectedProxyName ?? "No selection")
                .font(.callout)
                .foregroundStyle(group.selectedProxyName == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.10), in: .capsule)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(group.selectedProxyName ?? "No selection")")
    }
}

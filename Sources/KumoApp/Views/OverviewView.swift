import SwiftUI
import Charts
import KumoCoreKit

struct OverviewView: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    init(onNavigate: @escaping (SidebarDestination) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    var body: some View {
        HSplitView {
            OverviewProxySidebar(onNavigate: onNavigate)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                .frame(maxHeight: .infinity)

            OverviewControlPanel(onNavigate: onNavigate)
                .frame(minWidth: 360, idealWidth: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Left pane

private struct OverviewProxySidebar: View {
    @Environment(KumoAppStore.self) private var store
    @State private var search = ""
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.35)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search nodes", text: $search)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search proxy nodes")

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .kumoSubtleBackground(in: .capsule)
    }

    @ViewBuilder
    private var content: some View {
        if displayGroups.isEmpty {
            emptyState
        } else if filteredGroups.isEmpty {
            noResultsState
        } else {
            groupsScroll
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer(minLength: 32)
            KumoInlineState(
                title: "No Proxy Groups",
                systemImage: "point.3.connected.trianglepath.dotted",
                message: emptyStateMessage
            ) {
                Button("Open Profiles") {
                    onNavigate(.profiles)
                }
            }
            .padding(.horizontal, 14)
            Spacer()
        }
    }

    private var emptyStateMessage: String {
        isRunning
            ? "Import a profile that provides proxy groups."
            : "Import a profile that provides proxy groups to preview here."
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 40)
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No matching nodes")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var groupsScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredGroups) { group in
                    ProxyGroupSection(
                        group: group,
                        isSearchActive: isSearchActive,
                        isReadOnly: !isRunning
                    )
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollEdgeEffectStyleIfAvailable()
        // Dim the whole list while the core is stopped so it visually reads
        // as a non-interactive preview, not a stale live view.
        .opacity(isRunning ? 1.0 : 0.55)
    }

    private var isSearchActive: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isRunning: Bool {
        store.status.state == .running
    }

    /// Source of truth for what the sidebar renders: live mihomo groups when
    /// the core is running, the YAML-parsed read-only preview when it's
    /// stopped. Switches automatically the moment `status.state` flips.
    private var displayGroups: [ProxyGroup] {
        isRunning ? store.proxyGroups : store.profilePreviewGroups
    }

    private var filteredGroups: [ProxyGroup] {
        let groups = displayGroups
        guard isSearchActive else {
            return groups
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return groups.compactMap { group in
            let groupHit = group.name.lowercased().contains(query)
            let matchingProxies = group.proxies.filter { $0.name.lowercased().contains(query) }
            if !groupHit, matchingProxies.isEmpty {
                return nil
            }
            var copy = group
            // When the user typed a query, only show the matching subset so
            // long groups do not flood the list with non-matching rows.
            if !matchingProxies.isEmpty {
                copy.proxies = matchingProxies
            }
            return copy
        }
    }
}

private struct ProxyGroupSection: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = true
    let group: ProxyGroup
    let isSearchActive: Bool
    let isReadOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if effectiveExpansion {
                ForEach(group.proxies) { proxy in
                    ProxyNodeRow(group: group, proxy: proxy, isReadOnly: isReadOnly)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private var effectiveExpansion: Bool {
        // Force-open while a search is active so users can see matches without
        // a second click.
        isSearchActive || isExpanded
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                guard !isSearchActive else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(effectiveExpansion ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(group.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(group.proxies.count)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .kumoSubtleBackground(in: .capsule)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isSearchActive)

            Spacer(minLength: 4)

            Button {
                Task { await store.testDelay(for: group) }
            } label: {
                Image(systemName: "speedometer")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly || store.isTestingDelay)
            .help(isReadOnly ? "Start Kumo to test delay" : "Test delay for \(group.name)")
            .accessibilityLabel("Test delay for \(group.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct ProxyNodeRow: View {
    @Environment(KumoAppStore.self) private var store
    @State private var isHovered = false
    let group: ProxyGroup
    let proxy: ProxyNode
    let isReadOnly: Bool

    private var isSelected: Bool {
        // Preview groups always carry `selectedProxyName == nil`, so this is
        // naturally false in the stopped state — no need to gate on
        // isReadOnly.
        group.selectedProxyName == proxy.name
    }

    var body: some View {
        Button {
            Task { await store.selectProxy(group: group, proxy: proxy) }
        } label: {
            HStack(spacing: 10) {
                CountryFlagIcon(name: proxy.name, detectedCountry: proxy.detectedCountry)
                    .frame(width: 22, alignment: .center)

                Text(proxy.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DelayBadge(delay: proxy.delay)

                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 12)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowFill)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading || isReadOnly)
        .onHover { hovering in
            // Suppress the hover tint while read-only so the row never
            // visually invites a click that does nothing.
            isHovered = hovering && !isReadOnly
        }
        .contextMenu {
            if !isReadOnly {
                Button("Select \(proxy.name)") {
                    Task { await store.selectProxy(group: group, proxy: proxy) }
                }
                .disabled(isSelected)

                Button("Test Delay for Group") {
                    Task { await store.testDelay(for: group) }
                }
                .disabled(store.isTestingDelay)
            }
        }
        .accessibilityLabel(proxy.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.secondary.opacity(0.10)
        }
        return .clear
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if isSelected { parts.append("Selected") }
        if let delay = proxy.delay {
            parts.append(delay == 0 ? "Timeout" : "\(delay) ms")
        }
        return parts.joined(separator: ", ")
    }
}

private struct CountryFlagIcon: View {
    let name: String
    let detectedCountry: String?

    var body: some View {
        if let flag = resolvedFlag {
            Text(flag)
                .font(.system(size: 16))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "globe")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// Display priority:
    /// 1. Flag emoji / code already discoverable from the node `name` (zero
    ///    network cost, immediate).
    /// 2. `detectedCountry` from the async GeoIP lookup over the upstream
    ///    server IP (fills in when names like "Auto", "Relay 01" carry no
    ///    geographic signal).
    /// 3. Nothing — caller renders a globe placeholder.
    private var resolvedFlag: String? {
        if let nameFlag = ProxyCountry.flag(for: name) {
            return nameFlag
        }
        if let code = detectedCountry {
            return ProxyCountry.flag(forRegionCode: code)
        }
        return nil
    }
}

private struct DelayBadge: View {
    let delay: Int?

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var text: String {
        guard let delay else { return "—" }
        if delay == 0 { return "timeout" }
        return "\(delay) ms"
    }

    private var color: Color {
        guard let delay else { return .secondary }
        if delay == 0 { return .red }
        return delay < 300 ? .green : .orange
    }
}

// MARK: - Right pane

private struct OverviewControlPanel: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProfileCard(onNavigate: onNavigate)
                TrafficCard()
                SystemProxyCard(onNavigate: onNavigate)
                TunCard(onNavigate: onNavigate)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollEdgeEffectStyleIfAvailable()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ProfileCard: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let profile = store.currentProfile {
                if isExpanded {
                    metadataDetails(for: profile)
                        .transition(.opacity)
                }

                if let subscription = profile.subscriptionUserInfo {
                    Divider().opacity(0.4)
                    subscriptionSection(for: subscription, showsExpiry: isExpanded)
                }

                Divider().opacity(0.4)
                footer
            } else {
                emptyState
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 18)
    }

    /// The card no longer carries a generic "Current Profile" title — the
    /// profile's own name now lives in the header so the card has one less
    /// row to read. When there's no profile loaded we fall back to the
    /// generic label so the header doesn't disappear.
    private var headerTitle: String {
        store.currentProfile?.name ?? "Current Profile"
    }

    private var header: some View {
        Button(action: toggleExpansion) {
            HStack(alignment: .center, spacing: 10) {
                Label(headerTitle, systemImage: "rectangle.stack")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let profile = store.currentProfile {
                    kindBadges(for: profile)
                    chevron
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.currentProfile == nil)
        .accessibilityLabel("Current Profile: \(headerTitle)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hide profile details" : "Show profile details")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 14)
            .accessibilityHidden(true)
    }

    private func toggleExpansion() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            isExpanded.toggle()
        }
    }

    @ViewBuilder
    private func kindBadges(for profile: ProfileSummary) -> some View {
        HStack(spacing: 4) {
            Text(kindLabel(for: profile.kind))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .kumoSubtleBackground(in: .capsule)
            if profile.isSubStoreManaged {
                Text("Sub-Store")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .kumoSubtleBackground(in: .capsule)
            }
        }
    }

    private func kindLabel(for kind: ProfileKind) -> String {
        switch kind {
        case .local: "Local"
        case .remote: "Remote"
        case .inline: "Inline"
        }
    }

    /// Detail rows shown only when the card is expanded. The profile name
    /// itself stays at the top of the card regardless of expansion state —
    /// it's the one piece of metadata users want to see at a glance.
    private func metadataDetails(for profile: ProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledLine(title: "Updated", value: updatedText(for: profile))
            LabeledLine(title: "Source", value: sourceText(for: profile))
            LabeledLine(title: "Auto-Update", value: autoUpdateText(for: profile))
        }
    }

    private func updatedText(for profile: ProfileSummary) -> String {
        guard let date = profile.updatedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sourceText(for profile: ProfileSummary) -> String {
        let trimmed = profile.sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func autoUpdateText(for profile: ProfileSummary) -> String {
        guard profile.autoUpdate, let interval = profile.updateIntervalSeconds, interval > 0 else {
            return "Off"
        }
        if interval >= 86_400 {
            let days = max(1, interval / 86_400)
            return days == 1 ? "Every day" : "Every \(days) days"
        }
        if interval >= 3_600 {
            let hours = max(1, interval / 3_600)
            return hours == 1 ? "Every hour" : "Every \(hours) hours"
        }
        let minutes = max(1, interval / 60)
        return "Every \(minutes) min"
    }

    /// Subscription usage stays visible even when collapsed because data
    /// remaining is the single most useful piece of profile information.
    /// The expiry row, which is rarely consulted, only appears when
    /// `showsExpiry` is true.
    private func subscriptionSection(
        for subscription: SubscriptionUserInfo,
        showsExpiry: Bool
    ) -> some View {
        let used = subscription.upload + subscription.download
        let total = subscription.total
        let progress = total > 0 ? min(1.0, Double(used) / Double(total)) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if total > 0 {
                    Text("\(used.kumoByteCount) / \(total.kumoByteCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Text(used.kumoByteCount)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
            if total > 0 {
                ProgressView(value: progress)
                    .tint(Color.accentColor)
            }
            if showsExpiry, let expire = subscription.expire {
                LabeledLine(title: "Expires", value: expireText(from: expire))
                    .transition(.opacity)
            }
        }
    }

    private func expireText(from epoch: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(epoch))
            .formatted(date: .abbreviated, time: .omitted)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                guard let profile = store.currentProfile else { return }
                Task { await store.refreshProfile(profile) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isLoading || store.currentProfile == nil)

            Spacer()

            Button {
                onNavigate(.profiles)
            } label: {
                Label("Profiles", systemImage: "arrow.up.right.square")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            .buttonStyle(.borderless)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No profile loaded")
                .font(.subheadline.weight(.semibold))
            Text("Import a profile to start.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Profiles") {
                onNavigate(.profiles)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }
}

private struct TrafficCard: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 8) {
                speedRow(title: "Upload", value: store.trafficSnapshot.uploadSpeed, systemImage: "arrow.up")
                Divider().opacity(0.4)
                speedRow(title: "Download", value: store.trafficSnapshot.downloadSpeed, systemImage: "arrow.down")
            }

            if isExpanded {
                chartSection
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 18)
    }

    private var header: some View {
        Button(action: toggleExpansion) {
            HStack(alignment: .center, spacing: 10) {
                Label("Traffic", systemImage: "speedometer")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                chevron
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Traffic")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hide traffic chart" : "Show traffic chart")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 14)
            .accessibilityHidden(true)
    }

    private func toggleExpansion() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            isExpanded.toggle()
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if store.trafficHistory.isEmpty {
            chartPlaceholder
        } else {
            trafficChart
        }
    }

    private var trafficChart: some View {
        // Sparkle-style sparkline: a single AreaMark of upload + download
        // with a vertical gradient fade and a monotone curve. Axes and
        // legend are intentionally hidden — this is decoration meant to
        // show throughput shape, not exact values (the rows above carry
        // the precise numbers).
        Chart(store.trafficHistory) { sample in
            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("Speed", sample.total)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.65), Color.accentColor.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 80)
        .accessibilityLabel("Network traffic history, last 60 seconds")
        .accessibilityValue("Current total \((store.trafficSnapshot.uploadSpeed + store.trafficSnapshot.downloadSpeed).kumoByteCount) per second")
    }

    private var chartPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08))
            .frame(height: 80)
            .overlay {
                Text("Start Kumo to see traffic history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
    }

    private func speedRow(title: String, value: Int, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value.kumoByteCount)/s")
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value.kumoByteCount) per second")
    }
}

private struct SystemProxyCard: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        OverviewActionCard(
            title: "System Proxy",
            systemImage: "switch.2",
            isOn: store.status.systemProxyEnabled,
            isDisabled: !canToggle,
            disabledHint: canToggle ? nil : "Start Kumo to enable System Proxy.",
            toggleLabel: "System Proxy toggle",
            toggleAction: { isEnabled in
                store.setSystemProxyEnabled(isEnabled)
            },
            settingsAction: { onNavigate(.systemProxy) }
        ) {
            VStack(alignment: .leading, spacing: 4) {
                LabeledLine(title: "Endpoint", value: endpoint)
                LabeledLine(title: "Mode", value: settings.mode.displayName)
                LabeledLine(title: "Network", value: settings.networkService)
            }
        }
    }

    private var canToggle: Bool {
        store.status.systemProxyEnabled || store.status.state == .running
    }

    private var settings: SystemProxySettings {
        store.status.systemProxySettings ?? SystemProxySettings(
            host: store.status.endpoint.host,
            port: store.status.proxyPorts.mixedPort
        )
    }

    private var endpoint: String {
        "\(settings.host):\(settings.port)"
    }
}

private struct TunCard: View {
    @Environment(KumoAppStore.self) private var store
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        OverviewActionCard(
            title: "TUN",
            systemImage: store.tunStatus.isEnabled ? "lock.shield.fill" : "lock.shield",
            isOn: store.tunStatus.isEnabled,
            isDisabled: store.isLoading,
            disabledHint: nil,
            toggleLabel: "TUN toggle",
            toggleAction: { isEnabled in
                Task { await store.setTunEnabled(isEnabled) }
            },
            settingsAction: { onNavigate(.tun) }
        ) {
            VStack(alignment: .leading, spacing: 4) {
                LabeledLine(title: "Stack", value: stack)
                LabeledLine(title: "Auto-route", value: autoRoute)
                if let error = trimmedLastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                        .accessibilityLabel("TUN error: \(error)")
                }
            }
        }
    }

    private var stack: String {
        let raw = store.status.runtimeSettings?.tun?.stack ?? ""
        return raw.isEmpty ? "—" : raw
    }

    private var autoRoute: String {
        guard let tun = store.status.runtimeSettings?.tun else { return "—" }
        return tun.autoRoute ? "Enabled" : "Disabled"
    }

    private var trimmedLastError: String? {
        guard let error = store.tunStatus.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
              !error.isEmpty else {
            return nil
        }
        return error
    }
}

private struct OverviewActionCard<Summary: View>: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let isDisabled: Bool
    let disabledHint: String?
    let toggleLabel: String
    let toggleAction: (Bool) -> Void
    let settingsAction: () -> Void
    @ViewBuilder let summary: Summary

    init(
        title: String,
        systemImage: String,
        isOn: Bool,
        isDisabled: Bool,
        disabledHint: String?,
        toggleLabel: String,
        toggleAction: @escaping (Bool) -> Void,
        settingsAction: @escaping () -> Void,
        @ViewBuilder summary: () -> Summary
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.isDisabled = isDisabled
        self.disabledHint = disabledHint
        self.toggleLabel = toggleLabel
        self.toggleAction = toggleAction
        self.settingsAction = settingsAction
        self.summary = summary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.headline)

                Spacer()

                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { toggleAction($0) }
                )) {
                    Text(toggleLabel)
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isDisabled)
                .help(disabledHint ?? "")
                .accessibilityLabel(toggleLabel)
            }

            summary
                .font(.callout)
                .foregroundStyle(.secondary)

            if let disabledHint, isDisabled {
                Text(disabledHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button {
                    settingsAction()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 18)
    }
}

private struct LabeledLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

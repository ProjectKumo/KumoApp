import SwiftUI
import KumoCoreKit

struct ProxiesView: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedGroups: Set<String> = []
    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if store.proxyGroups.isEmpty {
                KumoPage(title: "Proxies") {
                    KumoEmptyState(
                        title: "No Proxy Groups",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        message: "Start Kumo or import a profile with proxy groups."
                    ) {
                        Button("Refresh") {
                            Task { await store.loadProxyGroups() }
                        }
                    }
                }
            } else {
                scrollContent
            }
        }
        .task {
            scheduleInitialGroupExpansion()
        }
        .onChange(of: store.proxyGroups) {
            scheduleInitialGroupExpansion()
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(store.proxyGroups) { group in
                    ProxyGroupCard(
                        group: group,
                        isExpanded: isExpanded(group),
                        namespace: glassNamespace,
                        onToggle: { toggleExpansion(for: group) }
                    )
                }
            }
            .padding(.bottom, 8)
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .contentMargins(.top, 24, for: .scrollContent)
        .contentMargins(.bottom, 32, for: .scrollContent)
        .scrollEdgeEffectStyleIfAvailable()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func isExpanded(_ group: ProxyGroup) -> Bool {
        expandedGroups.contains(group.id)
    }

    private func toggleExpansion(for group: ProxyGroup) {
        withAnimation(expansionAnimation) {
            if expandedGroups.contains(group.id) {
                expandedGroups.remove(group.id)
            } else {
                expandedGroups.insert(group.id)
            }
        }
    }

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }

    private func scheduleInitialGroupExpansion() {
        Task { @MainActor in
            await Task.yield()
            expandInitialGroupsIfNeeded()
        }
    }

    private func expandInitialGroupsIfNeeded() {
        if expandedGroups.isEmpty {
            expandedGroups = Set(store.proxyGroups.prefix(3).map(\.id))
        }
    }
}

private struct ProxyGroupCard: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: ProxyGroup
    let isExpanded: Bool
    let namespace: Namespace.ID
    let onToggle: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)
    ]

    var body: some View {
        groupContainer {
            VStack(alignment: .leading, spacing: 16) {
                groupHeader
                    .kumoGlassEffectID("group-\(group.id)", in: namespace)

                if isExpanded {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(group.proxies) { proxy in
                            ProxyCard(group: group, proxy: proxy)
                        }
                    }
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .contextMenu {
            Button("Test Delay") {
                Task { await store.testDelay(for: group) }
            }
        }
    }

    @ViewBuilder
    private func groupContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14, content: content)
        } else {
            content()
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    groupTitleContent
                    Spacer(minLength: 8)
                    chevron
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(group.selectedProxyName ?? "No selection")")
            .accessibilityHint(isExpanded ? "Collapse \(group.name)" : "Expand \(group.name)")

            testDelayButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoInteractiveGlass(cornerRadius: 18)
    }

    private var groupTitleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text("\(group.proxies.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .kumoSubtleBackground(in: .capsule)
            }
            Text(group.selectedProxyName ?? "No selection")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(isExpanded ? -180 : 0))
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isExpanded)
            .accessibilityHidden(true)
    }

    private var testDelayButton: some View {
        Button {
            Task { await store.testDelay(for: group) }
        } label: {
            Image(systemName: "speedometer")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.isTestingDelay)
        .help("Test delay for this group")
        .accessibilityLabel("Test delay for \(group.name)")
    }
}

private struct ProxyCard: View {
    @Environment(KumoAppStore.self) private var store
    let group: ProxyGroup
    let proxy: ProxyNode

    private var isSelected: Bool {
        group.selectedProxyName == proxy.name
    }

    var body: some View {
        Button {
            Task { await store.selectProxy(group: group, proxy: proxy) }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)
                    .contentTransition(.symbolEffect(.replace.downUp))

                VStack(alignment: .leading, spacing: 6) {
                    Text(proxy.name)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    metadataRow
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .contentShape(.rect)
            .kumoInteractiveGlass(cornerRadius: 16, tint: Color.accentColor.opacity(isSelected ? 0.16 : 0))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Select Proxy") {
                Task { await store.selectProxy(group: group, proxy: proxy) }
            }
        }
        .accessibilityLabel("Select \(proxy.name)")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if isSelected {
            values.append("Selected")
        }
        if !proxyTypeText.isEmpty {
            values.append("Protocol \(proxyTypeText)")
        }
        values.append(delayText)
        return values.joined(separator: ", ")
    }

    private var delayText: String {
        guard let delay = proxy.delay else {
            return "--"
        }
        if delay == 0 {
            return "Timeout"
        }
        return "\(delay) ms"
    }

    private var proxyTypeText: String {
        proxy.type?.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase ?? ""
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if !proxyTypeText.isEmpty {
                Text(proxyTypeText)
                    .foregroundStyle(.secondary)
            }
            Text(delayText)
                .foregroundStyle(delayColor)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
    }

    private var delayColor: Color {
        guard let delay = proxy.delay else {
            return Color.secondary.opacity(0.7)
        }
        if delay == 0 {
            return .red
        }
        return delay < 300 ? .green : .orange
    }
}

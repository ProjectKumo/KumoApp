import SwiftUI
import KumoCoreKit

struct ProxiesView: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var expandedGroups: Set<String> = []
    @FocusState private var isSearchFocused: Bool
    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if store.proxyGroups.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            scheduleInitialGroupExpansion()
        }
        .onChange(of: store.proxyGroups) {
            scheduleInitialGroupExpansion()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proxies")
                .font(.largeTitle.bold())
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
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader
                proxyGroupsContent
            }
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .contentMargins(.top, 24, for: .scrollContent)
        .contentMargins(.bottom, 32, for: .scrollContent)
        .scrollEdgeEffectStyleIfAvailable()
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Proxies")
                .font(.largeTitle.bold())
            Spacer(minLength: 16)
            inlineSearchField
                .frame(maxWidth: 240)
        }
    }

    private var inlineSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            TextField("Search proxies", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
        .kumoInteractiveGlass(cornerRadius: 10)
    }

    @ViewBuilder
    private var proxyGroupsContent: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                proxyGroupsStack
            }
        } else {
            proxyGroupsStack
        }
    }

    private var proxyGroupsStack: some View {
        LazyVStack(spacing: 18) {
            ForEach(filteredGroups) { group in
                ProxyGroupCard(
                    group: group,
                    isExpanded: isExpanded(group),
                    namespace: glassNamespace,
                    onToggle: { toggleExpansion(for: group) }
                )
            }
        }
    }

    private func isExpanded(_ group: ProxyGroup) -> Bool {
        isSearching || expandedGroups.contains(group.id)
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

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredGroups: [ProxyGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.proxyGroups
        }

        return store.proxyGroups.compactMap { group in
            let proxies = group.proxies.filter { proxy in
                proxy.name.localizedCaseInsensitiveContains(query)
                    || group.name.localizedCaseInsensitiveContains(query)
            }
            guard !proxies.isEmpty else {
                return nil
            }

            var copy = group
            copy.proxies = proxies
            return copy
        }
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
        VStack(alignment: .leading, spacing: 16) {
            groupHeader

            if isExpanded {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(group.proxies) { proxy in
                        ProxyCard(group: group, proxy: proxy, namespace: namespace)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contextMenu {
            Button("Test Delay") {
                Task { await store.testDelay(for: group) }
            }
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 14) {
            Button {
                onToggle()
            } label: {
                groupTitleContent
            }
            .buttonStyle(.plain)

            testDelayButton

            Button {
                onToggle()
            } label: {
                chevron
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(group.name)" : "Expand \(group.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoInteractiveGlass(cornerRadius: 18)
        .kumoGlassEffectID("group-\(group.id)", in: namespace)
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
                    .background(.secondary.opacity(0.10), in: .capsule)
            }
            Text(group.selectedProxyName ?? "No selection")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityLabel("\(group.name), \(group.selectedProxyName ?? "No selection")")
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(.rect)
            .rotationEffect(.degrees(isExpanded ? -180 : 0))
            .animation(chevronAnimation) { content in
                content
                    .scaleEffect(isExpanded ? 1.06 : 1.0)
                    .opacity(isExpanded ? 1.0 : 0.72)
            }
    }

    private var chevronAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.16)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: ProxyGroup
    let proxy: ProxyNode
    let namespace: Namespace.ID

    private var isSelected: Bool {
        group.selectedProxyName == proxy.name
    }

    var body: some View {
        Button {
            Task { await store.selectProxy(group: group, proxy: proxy) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.top, 1)
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                        .animation(selectionAnimation, value: isSelected)
                    Text(proxy.name)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }

                HStack {
                    Spacer()
                    delayView
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .contentShape(.rect)
            .kumoInteractiveGlass(cornerRadius: 16, tint: glassTint)
            .kumoGlassEffectID("proxy-\(group.id)-\(proxy.id)", in: namespace)
        }
        .buttonStyle(.plain)
        .animation(selectionAnimation) { content in
            content.opacity(isSelected ? 1.0 : 0.92)
        }
        .contextMenu {
            Button("Select Proxy") {
                Task { await store.selectProxy(group: group, proxy: proxy) }
            }
        }
        .accessibilityLabel("Select \(proxy.name)")
        .accessibilityValue(isSelected ? "Selected" : delayText)
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

    @ViewBuilder
    private var delayView: some View {
        if let delay = proxy.delay, delay > 0 {
            DelayBadge(text: "\(delay) ms", style: delay < 300 ? .green : .orange)
        } else {
            Text(delayText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var glassTint: Color? {
        isSelected ? Color.accentColor.opacity(0.16) : nil
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }
}

private struct DelayBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let style: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style)
            .contentTransition(.numericText())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(style.opacity(0.12), in: .capsule)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: text)
    }
}

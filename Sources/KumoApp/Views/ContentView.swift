import SwiftUI
import KumoCoreKit

enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case profiles = "Profiles"
    case proxies = "Proxies"
    case connections = "Connections"
    case logs = "Logs"
    case rules = "Rules"
    case core = "Core"
    case systemProxy = "System Proxy"
    case dns = "DNS"
    case tun = "TUN"
    case sniffer = "Sniffer"
    case resources = "Resources"
    case overrides = "Overrides"
    case subStore = "Sub-Store"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .overview: "cloud"
        case .profiles: "rectangle.stack"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .connections: "network"
        case .logs: "doc.text.magnifyingglass"
        case .rules: "list.bullet.rectangle"
        case .core: "cpu"
        case .systemProxy: "switch.2"
        case .dns: "globe"
        case .tun: "lock.shield"
        case .sniffer: "scope"
        case .resources: "shippingbox"
        case .overrides: "slider.horizontal.3"
        case .subStore: "square.stack.3d.up"
        }
    }
}

struct SidebarSection: Identifiable {
    let id: String
    let title: String
    let destinations: [SidebarDestination]
}

struct ContentView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var selection: SidebarDestination = .overview
    private let sections = [
        SidebarSection(id: "daily", title: "Daily", destinations: [.overview, .profiles, .proxies]),
        SidebarSection(id: "inspect", title: "Inspect", destinations: [.connections, .logs, .rules]),
        SidebarSection(
            id: "configure",
            title: "Configure",
            destinations: [.core, .systemProxy, .dns, .tun, .sniffer, .resources, .overrides, .subStore]
        )
    ]

    var body: some View {
        navigationRoot
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        if store.status.state == .running {
                            store.stopCore()
                        } else {
                            Task { await store.startCore() }
                        }
                    } label: {
                        Label(coreActionTitle, systemImage: coreActionSystemImage)
                    }
                    .disabled(store.isLoading)
                    .accessibilityLabel(coreActionTitle)

                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Refresh status and proxies")
                }
            }
            .alert(errorAlertTitle, isPresented: errorAlertBinding) {
                if isCoreNotFoundError {
                    Button("Open Core Settings") {
                        store.clearError()
                        selection = .core
                    }

                    Button("Scan Again") {
                        store.clearError()
                        store.refreshCoreCandidates()
                    }
                }

                Button("OK", role: .cancel) {
                    store.clearError()
                }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .task {
                await store.refreshAll()
            }
    }

    private var navigationRoot: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationDestination(for: SidebarDestination.self) { destination in
            detailView(for: destination)
        }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.destinations) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.rawValue, systemImage: destination.symbolName)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding {
            store.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                store.clearError()
            }
        }
    }

    private var errorAlertTitle: String {
        isCoreNotFoundError ? "Core Not Found" : "Kumo"
    }

    private var isCoreNotFoundError: Bool {
        store.errorMessage?.localizedCaseInsensitiveContains("core was not found") == true
    }

    private var coreActionTitle: String {
        store.status.state == .running ? "Stop Kumo" : "Start Kumo"
    }

    private var coreActionSystemImage: String {
        store.status.state == .running ? "stop.fill" : "play.fill"
    }

    @ViewBuilder
    private var detailView: some View {
        detailView(for: selection)
    }

    @ViewBuilder
    private func detailView(for destination: SidebarDestination) -> some View {
        switch destination {
        case .overview:
            OverviewView()
        case .profiles:
            ProfilesView()
        case .proxies:
            ProxiesView()
        case .connections:
            ConnectionsView()
        case .logs:
            LogsView()
        case .rules:
            RulesView()
        case .core:
            CoreView()
        case .systemProxy:
            SystemProxyView()
        case .dns:
            DNSView()
        case .tun:
            TunView()
        case .sniffer:
            SnifferView()
        case .resources:
            ResourcesView()
        case .overrides:
            OverridesView()
        case .subStore:
            SubStoreView()
        }
    }

}

struct FlowLayout<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func scrollEdgeEffectStyleIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

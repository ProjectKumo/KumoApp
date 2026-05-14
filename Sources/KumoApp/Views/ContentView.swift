import SwiftUI
import Observation
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
    case agentSkills = "Agent Skills"

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
        case .agentSkills: "puzzlepiece.extension"
        }
    }
}

struct SidebarSection: Identifiable {
    let id: String
    let title: String
    let destinations: [SidebarDestination]
}

@MainActor
@Observable
final class KumoNavigationState {
    var selection: SidebarDestination = .overview
}

struct ContentView: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(KumoNavigationState.self) private var navigation
    private let sections = [
        SidebarSection(id: "daily", title: "Daily", destinations: [.overview, .profiles, .proxies]),
        SidebarSection(id: "inspect", title: "Inspect", destinations: [.connections, .logs, .rules]),
        SidebarSection(
            id: "configure",
            title: "Configure",
            destinations: [.core, .systemProxy, .dns, .tun, .sniffer, .resources, .overrides, .subStore, .agentSkills]
        )
    ]

    var body: some View {
        navigationRoot
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: modeBinding) {
                        ForEach(OutboundMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.isLoading || store.status.state != .running)
                    .allowsHitTesting(!store.isSwitchingMode)
                    .help("Switch outbound mode")
                }

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
                    .help(coreActionTitle)

                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Refresh status and proxies")
                    .help("Refresh status and proxies")
                }
            }
            .alert(errorAlertTitle, isPresented: errorAlertBinding) {
                if isCoreNotFoundError {
                    Button("Open Core Settings") {
                        store.clearError()
                        navigation.selection = .core
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
        List(selection: selectionBinding) {
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

    private var modeBinding: Binding<OutboundMode> {
        Binding {
            store.status.mode
        } set: { mode in
            Task { await store.setMode(mode) }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        detailView(for: navigation.selection)
    }

    @ViewBuilder
    private func detailView(for destination: SidebarDestination) -> some View {
        switch destination {
        case .overview:
            OverviewView(onNavigate: navigateAction)
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
            DNSView(onNavigate: navigateAction)
        case .tun:
            TunView(onNavigate: navigateAction)
        case .sniffer:
            SnifferView(onNavigate: navigateAction)
        case .resources:
            ResourcesView()
        case .overrides:
            OverridesView()
        case .subStore:
            SubStoreView()
        case .agentSkills:
            AgentSkillsView()
        }
    }

    private var navigateAction: (SidebarDestination) -> Void {
        { destination in navigation.selection = destination }
    }

    private var selectionBinding: Binding<SidebarDestination?> {
        Binding {
            navigation.selection
        } set: { destination in
            if let destination {
                navigation.selection = destination
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

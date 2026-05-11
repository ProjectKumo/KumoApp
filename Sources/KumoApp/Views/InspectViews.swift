import AppKit
import SwiftUI
import KumoCoreKit

struct ConnectionsView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var searchText = ""
    @State private var selectedConnectionIDs: Set<ConnectionEntry.ID> = []
    @State private var sortOrder: [KeyPathComparator<ConnectionEntry>] = [
        KeyPathComparator(\ConnectionEntry.host)
    ]
    @State private var isConfirmingCloseAll = false

    var body: some View {
        KumoPage(title: "Connections") {
            if filteredConnections.isEmpty {
                KumoEmptyState(
                    title: emptyStateTitle,
                    systemImage: "network",
                    message: emptyStateMessage
                ) {
                    Button("Refresh") {
                        Task { await store.loadInspectData() }
                    }
                }
            } else {
                Table(sortedConnections, selection: $selectedConnectionIDs, sortOrder: $sortOrder) {
                    TableColumn("Host", value: \.host)
                    TableColumn("Process") { connection in
                        Text(connection.process ?? "-")
                    }
                    TableColumn("Rule") { connection in
                        Text(connection.rule ?? "-")
                    }
                    TableColumn("Upload", value: \.upload) { connection in
                        Text(connection.upload.kumoByteCount)
                    }
                    TableColumn("Download", value: \.download) { connection in
                        Text(connection.download.kumoByteCount)
                    }
                }
                .contextMenu(forSelectionType: ConnectionEntry.ID.self) { selection in
                    Button("Copy Host") {
                        copy(\.host, for: selection)
                    }
                    Button("Copy Process") {
                        copy(\.process, for: selection)
                    }
                    Button("Copy Rule") {
                        copy(\.rule, for: selection)
                    }
                    Divider()
                    Button(closeLabel(for: selection), role: .destructive) {
                        Task { await store.closeConnections(ids: selection) }
                    }
                    .disabled(selection.isEmpty || store.status.state != .running)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search connections")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    isConfirmingCloseAll = true
                } label: {
                    Label("Close All", systemImage: "xmark.circle")
                }
                .disabled(store.connections.isEmpty || store.status.state != .running)
                .help("Close every active connection")
            }
        }
        .confirmationDialog(
            "Close all \(store.connections.count) connections?",
            isPresented: $isConfirmingCloseAll,
            titleVisibility: .visible
        ) {
            Button("Close All", role: .destructive) {
                Task { await store.closeAllConnections() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Active TCP/UDP sessions tracked by Mihomo will be terminated. Apps may need to reconnect.")
        }
        .task {
            await store.loadInspectData()
        }
    }

    private func closeLabel(for selection: Set<ConnectionEntry.ID>) -> String {
        switch selection.count {
        case 0: "Close Connection"
        case 1: "Close Connection"
        default: "Close \(selection.count) Connections"
        }
    }

    private var sortedConnections: [ConnectionEntry] {
        filteredConnections.sorted(using: sortOrder)
    }

    private var filteredConnections: [ConnectionEntry] {
        guard !searchText.isEmpty else {
            return store.connections
        }

        return store.connections.filter {
            $0.host.localizedCaseInsensitiveContains(searchText)
                || ($0.process?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.rule?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "No Matches"
        }
        return store.status.state == .running ? "No Connections" : "Core Stopped"
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "Try another search term."
        }
        return store.status.state == .running
            ? "Active connections will appear here."
            : "Start Kumo to inspect traffic."
    }

    private func copy<Value>(_ keyPath: KeyPath<ConnectionEntry, Value?>, for selection: Set<ConnectionEntry.ID>) {
        let lines = sortedConnections
            .filter { selection.contains($0.id) }
            .compactMap { $0[keyPath: keyPath].map(String.init(describing:)) }
        guard !lines.isEmpty else { return }
        writeToPasteboard(lines.joined(separator: "\n"))
    }

    private func copy(_ keyPath: KeyPath<ConnectionEntry, String>, for selection: Set<ConnectionEntry.ID>) {
        let lines = sortedConnections
            .filter { selection.contains($0.id) }
            .map { $0[keyPath: keyPath] }
        guard !lines.isEmpty else { return }
        writeToPasteboard(lines.joined(separator: "\n"))
    }

    private func writeToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all
    case error
    case warning
    case info
    case debug

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Info"
        case .debug: "Debug"
        }
    }

    /// Underlying core log level filter passed to the controller. `nil`
    /// means "do not filter".
    var coreFilter: String? {
        self == .all ? nil : rawValue
    }
}

struct LogsView: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var level: LogLevelFilter = .all
    @State private var followsLiveLogs = false

    var body: some View {
        KumoPage(title: "Logs") {
            VStack(alignment: .leading, spacing: 10) {
                controlsRow

                if filteredLogs.isEmpty {
                    KumoEmptyState(
                        title: searchText.isEmpty ? "No Logs" : "No Matches",
                        systemImage: "doc.text.magnifyingglass",
                        message: searchText.isEmpty ? "Recent core logs will appear here." : "Try another search term."
                    ) {
                        Button("Refresh") {
                            Task { await store.loadInspectData() }
                        }
                    }
                } else {
                    List(filteredLogs) { log in
                        LogRow(log: log)
                            .contextMenu {
                                Button("Copy Message") {
                                    writeToPasteboard(log.message)
                                }
                                Button("Copy All Visible") {
                                    writeToPasteboard(filteredLogs.map(\.message).joined(separator: "\n"))
                                }
                            }
                    }
                    .scrollEdgeEffectStyleIfAvailable()
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search logs")
        .task {
            await store.loadInspectData()
        }
        .onChange(of: level) {
            guard followsLiveLogs else { return }
            store.startLogStream(level: level.coreFilter)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Picker("Level", selection: $level) {
                ForEach(LogLevelFilter.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Button {
                followsLiveLogs.toggle()
                if followsLiveLogs {
                    store.startLogStream(level: level.coreFilter)
                } else {
                    store.stopLogStream()
                }
            } label: {
                HStack(spacing: 6) {
                    if followsLiveLogs {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .symbolEffect(.pulse, isActive: followsLiveLogs && !reduceMotion)
                    }
                    Text(followsLiveLogs ? "Pause" : "Follow")
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(store.status.state != .running)
            .help(followsLiveLogs ? "Pause live log streaming" : "Stream live core logs")

            Button("Clear") {
                store.clearLogs()
            }
            .disabled(store.logs.isEmpty)
        }
    }

    private var filteredLogs: [LogEntry] {
        store.logs.filter { log in
            let matchesLevel = level == .all || log.level == level.rawValue
            let matchesSearch = searchText.isEmpty || log.message.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    private func writeToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

private struct LogRow: View {
    let log: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(log.level.uppercased())
                .font(.caption.monospaced())
                .foregroundStyle(levelColor)
                .frame(width: 64, alignment: .leading)
            Text(log.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            if let time = log.time {
                Spacer()
                Text(time)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var levelColor: Color {
        switch log.level {
        case "error": .red
        case "warning": .orange
        default: .secondary
        }
    }
}

struct RulesView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<RuleEntry>] = [
        KeyPathComparator(\RuleEntry.index)
    ]

    var body: some View {
        KumoPage(title: "Rules") {
            if filteredRules.isEmpty {
                KumoEmptyState(
                    title: searchText.isEmpty ? "No Rules" : "No Matches",
                    systemImage: "list.bullet.rectangle",
                    message: emptyStateMessage
                ) {
                    Button("Refresh") {
                        Task { await store.loadInspectData() }
                    }
                }
            } else {
                Table(sortedRules, sortOrder: $sortOrder) {
                    TableColumn("") { rule in
                        Toggle("Enable rule", isOn: Binding {
                            rule.isEnabled
                        } set: { isEnabled in
                            Task { await store.setRuleEnabled(rule, isEnabled: isEnabled) }
                        })
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .frame(width: 28, alignment: .center)
                    }
                    .width(32)

                    TableColumn("Type", value: \.type) { rule in
                        Text(rule.type)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Payload", value: \.payload) { rule in
                        Text(rule.payload.isEmpty ? "MATCH" : rule.payload)
                            .lineLimit(1)
                    }

                    TableColumn("Hit Rate") { rule in
                        if rule.hitRate != nil {
                            HitRateBadge(rule: rule)
                        } else {
                            Text("-")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Proxy", value: \.proxy) { rule in
                        Text(rule.proxy)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollEdgeEffectStyleIfAvailable()
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search rules")
        .task {
            await store.loadInspectData()
        }
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "Try another search term."
        }
        return store.status.state == .running
            ? "Rules will appear after the controller responds."
            : "Start Kumo to inspect rules."
    }

    private var sortedRules: [RuleEntry] {
        filteredRules.sorted(using: sortOrder)
    }

    private var filteredRules: [RuleEntry] {
        guard !searchText.isEmpty else {
            return store.rules
        }

        return store.rules.filter {
            $0.type.localizedCaseInsensitiveContains(searchText)
                || $0.payload.localizedCaseInsensitiveContains(searchText)
                || $0.proxy.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct HitRateBadge: View {
    let rule: RuleEntry
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Text(formattedHitRate)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .kumoSubtleBackground(in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show rule statistics")
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Hit", value: "\(rule.hitCount)")
                LabeledContent("Miss", value: "\(rule.missCount)")
                if let lastHit = rule.lastHit {
                    LabeledContent("Last hit", value: lastHit)
                }
                if let lastMiss = rule.lastMiss {
                    LabeledContent("Last miss", value: lastMiss)
                }
            }
            .padding(12)
            .frame(minWidth: 200)
        }
        .help("Show rule statistics")
    }

    private var formattedHitRate: String {
        guard let hitRate = rule.hitRate else { return "-" }
        return hitRate.formatted(.percent.precision(.fractionLength(1)))
    }
}

import SwiftUI
import KumoCoreKit

struct ConnectionsView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var searchText = ""

    var body: some View {
        KumoPage(title: "Connections") {
            if filteredConnections.isEmpty {
                KumoEmptyState(
                    title: "No Connections",
                    systemImage: "network",
                    message: store.status.state == .running ? "Active connections will appear here." : "Start Kumo to inspect traffic."
                ) {
                    Button("Refresh") {
                        Task { await store.loadInspectData() }
                    }
                }
            } else {
                Table(filteredConnections) {
                    TableColumn("Host", value: \.host)
                    TableColumn("Process") { connection in
                        Text(connection.process ?? "-")
                    }
                    TableColumn("Rule") { connection in
                        Text(connection.rule ?? "-")
                    }
                    TableColumn("Traffic") { connection in
                        Text("\(connection.upload.kumoByteCount) / \(connection.download.kumoByteCount)")
                    }
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search connections")
            }
        }
        .task {
            await store.loadInspectData()
        }
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
}

struct LogsView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var searchText = ""
    @State private var level = "all"

    var body: some View {
        KumoPage(title: "Logs") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Level", selection: $level) {
                    Text("All").tag("all")
                    Text("Error").tag("error")
                    Text("Warning").tag("warning")
                    Text("Info").tag("info")
                    Text("Debug").tag("debug")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if filteredLogs.isEmpty {
                    KumoEmptyState(
                        title: "No Logs",
                        systemImage: "doc.text.magnifyingglass",
                        message: "Recent core logs will appear here."
                    ) {
                        Button("Refresh") {
                            Task { await store.loadInspectData() }
                        }
                    }
                } else {
                    List(filteredLogs) { log in
                        HStack(alignment: .top, spacing: 10) {
                            Text(log.level.uppercased())
                                .font(.caption.monospaced())
                                .foregroundStyle(log.level == "error" ? .red : .secondary)
                                .frame(width: 64, alignment: .leading)
                            Text(log.message)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .searchable(text: $searchText, placement: .toolbar, prompt: "Search logs")
                    .scrollEdgeEffectStyleIfAvailable()
                }
            }
        }
        .task {
            await store.loadInspectData()
        }
    }

    private var filteredLogs: [LogEntry] {
        store.logs.filter { log in
            let matchesLevel = level == "all" || log.level == level
            let matchesSearch = searchText.isEmpty || log.message.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }
}

struct RulesView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var searchText = ""

    var body: some View {
        KumoPage(title: "Rules") {
            if filteredRules.isEmpty {
                KumoEmptyState(
                    title: "No Rules",
                    systemImage: "list.bullet.rectangle",
                    message: store.status.state == .running ? "Rules will appear after the controller responds." : "Start Kumo to inspect rules."
                ) {
                    Button("Refresh") {
                        Task { await store.loadInspectData() }
                    }
                }
            } else {
                List(filteredRules) { rule in
                    HStack(spacing: 12) {
                        Text(rule.type)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                        Text(rule.payload)
                            .lineLimit(1)
                        Spacer()
                        Text(rule.proxy)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search rules")
                .scrollEdgeEffectStyleIfAvailable()
            }
        }
        .task {
            await store.loadInspectData()
        }
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

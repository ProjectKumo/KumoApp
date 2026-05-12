import SwiftUI
import KumoCoreKit

// MARK: - Settings section

struct SubStoreSettingsSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var raw: String = "{}"
    @State private var parseError: String?
    @State private var lastLoadedVersion: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Sub-Store backend settings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Backup to Gist (upload)") {
                        Task { await subStore.performGistBackup(action: "upload") }
                    }
                    Button("Restore from Gist (download)") {
                        Task { await subStore.performGistBackup(action: "download") }
                    }
                } label: {
                    Label("Gist", systemImage: "icloud")
                }
                .menuStyle(.button)
                Button {
                    Task {
                        await subStore.refreshSettings()
                        load()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload settings from backend")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $raw)
                    .font(.body.monospaced())
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                if let parseError {
                    Label(parseError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(8)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Reset") { load() }
                    Button("Apply") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(parseError != nil)
                }
                .padding(8)
            }
        }
        .task {
            if subStore.settings.raw.isEmpty {
                await subStore.refreshSettings()
            }
            load()
        }
        .onChange(of: subStore.settings.raw) {
            load()
        }
    }

    private func load() {
        guard let data = try? JSONEncoder.subStorePretty.encode(subStore.settings.raw),
              let text = String(data: data, encoding: .utf8) else {
            raw = "{}"
            parseError = nil
            return
        }
        raw = text
        parseError = nil
    }

    private func apply() {
        guard let data = raw.data(using: .utf8) else {
            parseError = "Invalid encoding"
            return
        }
        do {
            let dict = try JSONDecoder().decode([String: JSONValue].self, from: data)
            parseError = nil
            Task { await subStore.saveSettings(SubStoreSettings(raw: dict)) }
        } catch {
            parseError = "JSON: \(error.localizedDescription)"
        }
    }
}

// MARK: - Logs section

struct SubStoreLogsSection: View {
    @Environment(SubStoreStore.self) private var subStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.logs.count) log entries")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await subStore.refreshLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if subStore.logs.isEmpty {
                ContentUnavailableView(
                    "No log entries yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Sub-Store records actions like syncs and parser errors. Refresh to load the latest.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(subStore.logs) { (entry: SubStoreLogEntry) in
                            LogRowView(entry: entry)
                            Divider()
                        }
                    }
                }
            }
        }
    }

}

private struct LogRowView: View {
    let entry: SubStoreLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let level = entry.level {
                Text(level.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelTint(level).opacity(0.18), in: .capsule)
                    .foregroundStyle(levelTint(level))
            }
            if let time = entry.time {
                Text(Date(timeIntervalSince1970: TimeInterval(time)).formatted(.dateTime.hour().minute().second()))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
            }
            Text(entry.message)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func levelTint(_ level: String) -> Color {
        switch level.lowercased() {
        case "error", "fatal": .red
        case "warn", "warning": .orange
        case "info": .accentColor
        case "debug": .secondary
        default: .secondary
        }
    }
}

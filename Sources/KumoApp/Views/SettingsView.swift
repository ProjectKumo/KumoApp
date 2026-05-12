import ServiceManagement
import SwiftUI
import KumoCoreKit

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }

            Tab("Updates", systemImage: "arrow.down.circle") {
                UpdateSettingsTab()
            }
        }
        .frame(width: 560)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(KumoAppStore.self) private var store
    @State private var launchAtLoginErrorMessage: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at Login", isOn: launchAtLoginBinding)
                if let launchAtLoginErrorMessage {
                    Text(launchAtLoginErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Quit when last window closes", isOn: quitOnLastWindowCloseBinding)
            } header: {
                Text("Window")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .task {
            store.loadPreferences()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            store.preferences.launchAtLogin
        } set: { value in
            updateLaunchAtLogin(value)
        }
    }

    private var quitOnLastWindowCloseBinding: Binding<Bool> {
        Binding {
            store.preferences.quitOnLastWindowClose
        } set: { value in
            var prefs = store.preferences
            prefs.quitOnLastWindowClose = value
            store.updatePreferences(prefs)
        }
    }

    private func updateLaunchAtLogin(_ value: Bool) {
        var prefs = store.preferences
        prefs.launchAtLogin = value
        store.updatePreferences(prefs)
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = "macOS rejected the change: \(error.localizedDescription). Move Kumo.app to /Applications and try again."
        }
    }
}

private struct UpdateSettingsTab: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        Form {
            Section("Channel") {
                Picker("Update Channel", selection: channelBinding) {
                    ForEach(AppUpdateChannel.allCases, id: \.self) { channel in
                        Text(channel.rawValue.capitalized).tag(channel)
                    }
                }
            }

            Section("Release Feed") {
                TextField(
                    "Custom Manifest URL",
                    text: manifestURLBinding,
                    prompt: Text("Default GitHub Releases feed")
                )
                .textFieldStyle(.roundedBorder)
                Text("Leave blank to use Kumo's GitHub Releases feed for the selected channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await store.checkForUpdate() }
                } label: {
                    if store.isCheckingForUpdates {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check for Updates Now")
                    }
                }
                .disabled(store.isCheckingForUpdates || store.isDownloadingUpdate || store.isInstallingUpdate)

                if let result = store.lastUpdateCheckResult {
                    LabeledContent("Current", value: result.currentVersion)
                    if let manifest = result.update {
                        LabeledContent("Available", value: manifest.version)
                        if manifest.canInstallAutomatically {
                            Button {
                                Task { await store.downloadAndInstallUpdate(manifest) }
                            } label: {
                                Text(store.isInstallingUpdate ? "Preparing Installer..." : "Download and Install")
                            }
                            .disabled(store.isDownloadingUpdate || store.isInstallingUpdate)
                        } else {
                            Link("Open Download Page", destination: manifest.downloadURL)
                        }
                    } else {
                        Text("You are on the latest \(store.preferences.updateChannel.rawValue) build.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.isDownloadingUpdate {
                    ProgressView(value: store.updateDownloadProgress ?? 0)
                }

                if let updateStatusMessage = store.updateStatusMessage {
                    Text(updateStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .task {
            store.loadPreferences()
        }
    }

    private var channelBinding: Binding<AppUpdateChannel> {
        Binding {
            store.preferences.updateChannel
        } set: { value in
            var prefs = store.preferences
            prefs.updateChannel = value
            store.updatePreferences(prefs)
        }
    }

    private var manifestURLBinding: Binding<String> {
        Binding {
            store.preferences.updateManifestURL?.absoluteString ?? ""
        } set: { value in
            var prefs = store.preferences
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            prefs.updateManifestURL = trimmed.isEmpty ? nil : URL(string: trimmed)
            store.updatePreferences(prefs)
        }
    }
}

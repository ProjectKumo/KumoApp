import ServiceManagement
import SwiftUI
import KumoCoreKit

struct SettingsView: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }

            Tab("Preferences", systemImage: "switch.2") {
                PreferencesSettingsTab()
            }

            Tab("Updates", systemImage: "arrow.down.circle") {
                UpdateSettingsTab()
            }
        }
        .frame(width: 560)
        .task {
            await store.refreshAll()
        }
    }
}

private struct GeneralSettingsTab: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Profile", value: store.currentProfile?.name ?? "Default")
                LabeledContent("Mode", value: store.status.mode.displayName)
                LabeledContent("System Proxy", value: store.status.systemProxyEnabled ? "On" : "Off")
            }

            Section("About") {
                LabeledContent("Version", value: bundleShortVersion)
                LabeledContent("Build", value: bundleBuild)
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private var bundleShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var bundleBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

private struct PreferencesSettingsTab: View {
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

            Section("Manifest") {
                TextField(
                    "Manifest URL",
                    text: manifestURLBinding,
                    prompt: Text("https://example.com/kumo-update.json")
                )
                .textFieldStyle(.roundedBorder)
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
                .disabled(store.preferences.updateManifestURL == nil || store.isCheckingForUpdates)

                if let result = store.lastUpdateCheckResult {
                    LabeledContent("Current", value: result.currentVersion)
                    if let manifest = result.update {
                        LabeledContent("Available", value: manifest.version)
                        Link("Open Download Page", destination: manifest.downloadURL)
                    } else {
                        Text("You are on the latest \(store.preferences.updateChannel.rawValue) build.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

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
    @State private var cliStatus: CLILinkStatus?
    @State private var cliBusy = false
    @State private var cliErrorMessage: String?

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

            Section("Setup") {
                LabeledContent("First-Run Setup") {
                    Button("Run Setup Again") {
                        store.reopenOnboarding()
                    }
                }

                LabeledContent("Command Line Tool") {
                    HStack(spacing: 10) {
                        cliStatusBadge

                        if cliBusy {
                            ProgressView().controlSize(.small)
                        }

                        if let cliStatus, cliStatus.isInstalled {
                            Button("Remove") {
                                Task { await uninstallCLI() }
                            }
                            .disabled(cliBusy)
                        } else {
                            Button(cliStatus?.state == .bundledCLIMissing ? "Unavailable" : "Install") {
                                Task { await installCLI() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(cliBusy || cliStatus?.state == .bundledCLIMissing)
                        }
                    }
                }

                if let cliErrorMessage {
                    Text(cliErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let cliStatus, !cliStatus.message.isEmpty {
                    Text(cliStatus.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .task {
            store.loadPreferences()
            refreshCLIStatus()
        }
    }

    @ViewBuilder
    private var cliStatusBadge: some View {
        if let cliStatus {
            switch cliStatus.state {
            case .installed:
                Label("Installed", systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.caption)
            case .notInstalled:
                Label("Not Installed", systemImage: "terminal")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            case .differentSymlink, .occupiedByOther:
                Label("Conflict", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .font(.caption)
            case .bundledCLIMissing:
                Label("Unavailable", systemImage: "questionmark.diamond")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func refreshCLIStatus() {
        cliStatus = store.controller.cliLinkStatus()
    }

    private func installCLI() async {
        guard !cliBusy else { return }
        cliBusy = true
        cliErrorMessage = nil
        defer { cliBusy = false }
        do {
            cliStatus = try store.controller.installCLILink()
        } catch {
            cliErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uninstallCLI() async {
        guard !cliBusy else { return }
        cliBusy = true
        cliErrorMessage = nil
        defer { cliBusy = false }
        do {
            cliStatus = try store.controller.uninstallCLILink()
        } catch {
            cliErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

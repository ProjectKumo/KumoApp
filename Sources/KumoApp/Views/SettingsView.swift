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
    @Environment(LocalizationManager.self) private var localizationManager
    @State private var launchAtLoginErrorMessage: String?
    @State private var cliStatus: CLILinkStatus?
    @State private var cliBusy = false
    @State private var cliErrorMessage: String?
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            Section(String(localized: "Startup")) {
                Toggle(String(localized: "Open at Login"), isOn: launchAtLoginBinding)
                if let launchAtLoginErrorMessage {
                    Text(launchAtLoginErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle(String(localized: "Quit when last window closes"), isOn: quitOnLastWindowCloseBinding)
            } header: {
                Text(String(localized: "Window"))
            }

            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Language"), selection: languageBinding) {
                    Text(localizationManager.systemDisplayName())
                        .tag(Optional<String>.none)
                    ForEach(localizationManager.availableLanguages, id: \.self) { code in
                        Text(localizationManager.displayName(for: code))
                            .tag(Optional<String>.some(code))
                    }
                }

                if localizationManager.needsRestart {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(String(localized: "Restart Required"))
                            .font(.caption)
                        Spacer()
                        Button(String(localized: "Restart Now")) {
                            showRestartAlert = true
                        }
                        .controlSize(.small)
                        .alert(String(localized: "Restart Kumo?"), isPresented: $showRestartAlert) {
                            Button(String(localized: "Restart Now"), role: .destructive) {
                                restartApp()
                            }
                            Button(String(localized: "Later"), role: .cancel) { }
                        } message: {
                            Text(String(localized: "Kumo must restart to apply the language change."))
                        }
                    }
                }
            }

            Section(String(localized: "Setup")) {
                LabeledContent("First-Run Setup") {
                    Button(String(localized: "Run Setup Again")) {
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
                            Button(String(localized: "Remove")) {
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
                Label(String(localized: "Installed"), systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.caption)
            case .notInstalled:
                Label(String(localized: "Not Installed"), systemImage: "terminal")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            case .differentSymlink, .occupiedByOther:
                Label(String(localized: "Conflict"), systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .font(.caption)
            case .bundledCLIMissing:
                Label(String(localized: "Unavailable"), systemImage: "questionmark.diamond")
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

    private var languageBinding: Binding<String?> {
        Binding {
            store.preferences.appLanguage
        } set: { value in
            var prefs = store.preferences
            prefs.appLanguage = value
            store.updatePreferences(prefs)
            localizationManager.selectLanguage(value)
        }
    }

    private func restartApp() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appURL.path]
        try? task.run()
        NSApp.terminate(nil)
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
            let format = String(localized: LocalizedStringResource("macOS rejected the change: %@. Move Kumo.app to /Applications and try again."))
            launchAtLoginErrorMessage = String(format: format, error.localizedDescription)
        }
    }
}

private struct UpdateSettingsTab: View {
    @Environment(KumoAppStore.self) private var store

    var body: some View {
        Form {
            Section(String(localized: "Channel")) {
                Picker(String(localized: "Update Channel"), selection: channelBinding) {
                    ForEach(AppUpdateChannel.allCases, id: \.self) { channel in
                        Text(channel.rawValue.capitalized).tag(channel)
                    }
                }
            }

            Section(String(localized: "Release Feed")) {
                TextField(
                    "Custom Manifest URL",
                    text: manifestURLBinding,
                    prompt: Text(String(localized: "Default GitHub Releases feed"))
                )
                .textFieldStyle(.roundedBorder)
                Text(String(localized: "Leave blank to use Kumo's GitHub Releases feed for the selected channel."))
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
                        Text(String(localized: "Check for Updates Now"))
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
                                if store.isInstallingUpdate {
                                    Text(String(localized: "Preparing Installer..."))
                                } else {
                                    Text(String(localized: "Download and Install"))
                                }
                            }
                            .disabled(store.isDownloadingUpdate || store.isInstallingUpdate)
                        } else {
                            Link(String(localized: "Open Download Page"), destination: manifest.downloadURL)
                        }
                    } else {
                        Text(String(format: String(localized: "You are on the latest %@ build."), store.preferences.updateChannel.rawValue))
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

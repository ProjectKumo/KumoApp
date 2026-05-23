import AppKit
import SwiftUI
import KumoCoreKit

struct AboutView: View {
    @Environment(KumoAppStore.self) private var store

    private var bundleShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var bundleBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            AboutHeaderSection(version: bundleShortVersion, build: bundleBuild)
            Divider()
            AboutProjectSection()
            Divider()
            AboutUpdateSection(
                channel: store.preferences.updateChannel,
                isCheckingForUpdates: store.isCheckingForUpdates,
                isDownloadingUpdate: store.isDownloadingUpdate,
                isInstallingUpdate: store.isInstallingUpdate,
                downloadProgress: store.updateDownloadProgress,
                statusMessage: store.updateStatusMessage,
                result: store.lastUpdateCheckResult,
                checkForUpdates: checkForUpdates,
                installUpdate: installUpdate
            )
        }
        .padding(28)
        .frame(minWidth: 440, minHeight: 390, alignment: .topLeading)
        .task {
            store.loadPreferences()
        }
    }

    private func checkForUpdates() {
        Task { await store.checkForUpdate() }
    }

    private func installUpdate(_ manifest: AppUpdateManifest) {
        Task { await store.downloadAndInstallUpdate(manifest) }
    }
}

private struct AboutHeaderSection: View {
    let version: String
    let build: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "Kumo"))
                    .font(.largeTitle.weight(.semibold))
                Text(String(localized: "Native macOS Mihomo client"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "Version %@ (%@)"), version, build))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AboutProjectSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Project"))
                .font(.headline)

            Text(String(localized: "Manage profiles, proxy groups, system proxy, and Mihomo runtime state from a native Mac app."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text(String(localized: "Author"))
                        .foregroundStyle(.secondary)
                    Link(String(localized: "ProjectKumo"), destination: AboutLinks.author)
                }

                GridRow {
                    Text(String(localized: "Source"))
                        .foregroundStyle(.secondary)
                    Link(String(localized: "Kumo on GitHub"), destination: AboutLinks.project)
                }

                GridRow {
                    Text(String(localized: "Website"))
                        .foregroundStyle(.secondary)
                    Link(String(localized: "usekumo.app"), destination: AboutLinks.website)
                }

                GridRow {
                    Text(String(localized: "Releases"))
                        .foregroundStyle(.secondary)
                    Link(String(localized: "GitHub Releases"), destination: AboutLinks.releases)
                }

                GridRow {
                    Text(String(localized: "Channel"))
                        .foregroundStyle(.secondary)
                    Link(String(localized: "Telegram"), destination: AboutLinks.telegram)
                }
            }
            .font(.callout)
            .controlSize(.small)
        }
    }
}

private struct AboutUpdateSection: View {
    let channel: AppUpdateChannel
    let isCheckingForUpdates: Bool
    let isDownloadingUpdate: Bool
    let isInstallingUpdate: Bool
    let downloadProgress: Double?
    let statusMessage: String?
    let result: AppUpdateCheckResult?
    let checkForUpdates: () -> Void
    let installUpdate: (AppUpdateManifest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Updates"))
                .font(.headline)

            HStack(spacing: 10) {
                Button(action: checkForUpdates) {
                    if isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "Check for Updates"))
                    }
                }
                .disabled(isCheckingForUpdates || isDownloadingUpdate || isInstallingUpdate)

                if let manifest = result?.update {
                    if manifest.canInstallAutomatically {
                        Button(String(localized: "Download and Install")) {
                            installUpdate(manifest)
                        }
                        .disabled(isCheckingForUpdates || isDownloadingUpdate || isInstallingUpdate)
                    } else {
                        Link(String(localized: "Open Download Page"), destination: manifest.downloadURL)
                    }
                }
            }

            AboutUpdateStatusView(
                channel: channel,
                isDownloadingUpdate: isDownloadingUpdate,
                isInstallingUpdate: isInstallingUpdate,
                downloadProgress: downloadProgress,
                statusMessage: statusMessage,
                result: result
            )
        }
    }
}

private struct AboutUpdateStatusView: View {
    let channel: AppUpdateChannel
    let isDownloadingUpdate: Bool
    let isInstallingUpdate: Bool
    let downloadProgress: Double?
    let statusMessage: String?
    let result: AppUpdateCheckResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isDownloadingUpdate {
                ProgressView(value: downloadProgress ?? 0)
                    .frame(maxWidth: 260)
                Text(statusMessage ?? "Downloading update...")
            } else if isInstallingUpdate {
                Text(statusMessage ?? "Preparing installer...")
            } else if let result {
                checkedStatus(for: result)
            } else {
                Text(String(format: String(localized: "Current channel: %@. Updates are checked from GitHub Releases."), channel.rawValue.capitalized))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func checkedStatus(for result: AppUpdateCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let manifest = result.update {
                Text(String(format: String(localized: "Version %@ is available."), manifest.version))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                if let releaseNotes = manifest.releaseNotes, !releaseNotes.isEmpty {
                    Text(releaseNotes)
                        .font(.caption)
                        .lineLimit(4)
                }
                if !manifest.canInstallAutomatically {
                    Link(String(localized: "Open Download Page"), destination: manifest.downloadURL)
                        .controlSize(.small)
                }
            } else {
                Text(String(format: String(localized: "You are on the latest %@ build."), channel.rawValue))
            }
        }
    }
}

private enum AboutLinks {
    static let author = URL(string: "https://github.com/ProjectKumo")!
    static let project = URL(string: "https://github.com/ProjectKumo/KumoApp")!
    static let website = URL(string: "https://usekumo.app")!
    static let releases = URL(string: "https://github.com/ProjectKumo/KumoApp/releases")!
    static let telegram = URL(string: "https://t.me/projectkumo")!
}

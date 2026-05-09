import AppKit
import Foundation
import KumoCoreKit
import ServiceManagement

/// Glue that lets `NSApplication` consult our SwiftUI `KumoAppStore` (via
/// `KumoAppContext.shared`) for behaviours that SwiftUI does not yet model
/// natively: window-close termination policy, dock badge, Services menu,
/// Spotlight indexing, and SMAppService synchronisation.
@MainActor
final class KumoAppDelegate: NSObject, NSApplicationDelegate {
    private let preferencesStore = UserPreferencesStore()
    private var dockBadgeTimer: Timer?

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        synchronizeLaunchAtLogin()
        registerServicesProvider()
        startDockBadgeObserver()
        Task {
            await reindexSpotlightProfiles()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockBadgeTimer?.invalidate()
        dockBadgeTimer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        preferencesStore.load().quitOnLastWindowClose
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        return KumoAppContext.shared.handleUserActivity(userActivity)
    }

    // MARK: - LaunchAtLogin

    private func synchronizeLaunchAtLogin() {
        let prefs = preferencesStore.load()
        let service = SMAppService.mainApp
        let isRegistered = service.status == .enabled
        do {
            if prefs.launchAtLogin && !isRegistered {
                try service.register()
            } else if !prefs.launchAtLogin && isRegistered {
                try service.unregister()
            }
        } catch {
            // Surfaced lazily through SettingsView when the user toggles again.
        }
    }

    // MARK: - Dock badge

    private func startDockBadgeObserver() {
        // Timer fires on the main run loop, so `updateDockBadge` already
        // runs on the main thread; the closure does not need to spawn a
        // Task and does not need to capture self for cross-actor handoff.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                let count = KumoAppContext.shared.store?.connections.count ?? 0
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        dockBadgeTimer = timer
    }

    // MARK: - Spotlight

    private func reindexSpotlightProfiles() async {
        guard let store = KumoAppContext.shared.store else { return }
        // Refresh first so we index the current set, not the empty default.
        store.refreshProfiles()
        await SpotlightIndexer.shared.reindex(profiles: store.profiles)
    }

    // MARK: - Services menu

    private func registerServicesProvider() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Receives URL strings from the Services menu (registered via
    /// `NSServices` in Info.plist) and triggers profile import. macOS may
    /// invoke services from a non-main thread, so we hop back via a Task.
    @objc nonisolated func importProfileURL(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let raw = pasteboard.string(forType: .string) else {
            error.pointee = "Kumo: pasteboard did not contain text." as NSString
            return
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmed) != nil else {
            error.pointee = "Kumo: not a valid URL." as NSString
            return
        }

        Task { @MainActor in
            guard let store = KumoAppContext.shared.store else {
                return
            }
            await store.importRemoteProfile(urlString: trimmed, useProxy: false)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

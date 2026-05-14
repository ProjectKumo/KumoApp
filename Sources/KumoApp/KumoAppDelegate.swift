import AppKit
import Foundation
import KumoCoreKit
import os
import ServiceManagement
import UserNotifications

private let terminationLogger = Logger(subsystem: "io.kumo.KumoApp", category: "shutdown")

/// Single-resume gate so the first finisher in a cleanup/timeout race
/// resumes the continuation and the loser is a no-op. Lives on the main
/// actor to avoid needing a lock — both racers hop to `@MainActor` first.
@MainActor
private final class TerminationGate {
    private var resumed = false
    func claim() -> Bool {
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

/// Glue that lets `NSApplication` consult our SwiftUI `KumoAppStore` (via
/// `KumoAppContext.shared`) for behaviours that SwiftUI does not yet model
/// natively: window-close termination policy, dock badge, Services menu,
/// Spotlight indexing, and SMAppService synchronisation.
@MainActor
final class KumoAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let preferencesStore = UserPreferencesStore()
    private var dockBadgeTimer: Timer?
    private var statusItemController: KumoStatusItemController?
    private var isPerformingTerminationCleanup = false
    private var didCompleteTerminationCleanup = false

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        AppNotificationCoordinator.shared.registerCategories()
        Task {
            await AppNotificationCoordinator.shared.requestAuthorization()
        }
        statusItemController = KumoStatusItemController()
        synchronizeLaunchAtLogin()
        registerServicesProvider()
        startDockBadgeObserver()
        Task {
            await reindexSpotlightProfiles()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KumoAppContext.shared.store?.stopUpdatePolling()
        dockBadgeTimer?.invalidate()
        dockBadgeTimer = nil
        statusItemController?.invalidate()
        statusItemController = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCompleteTerminationCleanup else {
            return .terminateNow
        }
        guard !isPerformingTerminationCleanup else {
            return .terminateLater
        }

        isPerformingTerminationCleanup = true
        Task { @MainActor in
            await self.runTerminationCleanupWithTimeout(seconds: 5)
            self.didCompleteTerminationCleanup = true
            self.isPerformingTerminationCleanup = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Race the store's `prepareForTermination` against a hard timeout. The
    /// timeout bounds total quit wait at ~5 s so a hung helper-IPC stop or
    /// stuck `networksetup` invocation can't keep AppKit in
    /// `.terminateLater` forever — Sparkle's SIGKILL ladder caps at +6 s,
    /// this is the Swift analogue at the call site.
    @MainActor
    private func runTerminationCleanupWithTimeout(seconds: TimeInterval) async {
        guard let store = KumoAppContext.shared.store else { return }
        let cleanup = Task { @MainActor in
            await store.prepareForTermination()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = TerminationGate()
            Task { @MainActor in
                _ = await cleanup.value
                if gate.claim() { continuation.resume() }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if gate.claim() {
                    terminationLogger.error("Kumo termination cleanup exceeded \(Int(seconds))s; proceeding with quit")
                    continuation.resume()
                }
            }
        }
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list, .banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let manifest = AppNotificationCoordinator.manifest(from: userInfo)
        let version = AppNotificationCoordinator.version(from: userInfo)
        completionHandler()
        Task { @MainActor in
            self.handleNotificationResponse(
                actionIdentifier: actionIdentifier,
                manifest: manifest,
                version: version
            )
        }
    }

    private func handleNotificationResponse(
        actionIdentifier: String,
        manifest: AppUpdateManifest?,
        version: String?
    ) {
        guard let store = KumoAppContext.shared.store else {
            KumoAppContext.shared.openMainWindow()
            return
        }
        Task {
            await store.handleNotificationAction(
                actionIdentifier: actionIdentifier,
                manifest: manifest,
                version: version
            )
        }
    }
}

import AppKit
import Foundation
import KumoCoreKit

/// Single bridge that lets `NSApplicationDelegate` reach the SwiftUI-owned
/// `KumoAppStore`. The store is created in `KumoApp` and then attached here
/// from a `.task` modifier on the root view, so any non-SwiftUI hook
/// (`NSApp.servicesProvider`, dock badge timer, Spotlight handlers, App
/// Intents) can resolve the live store via `KumoAppContext.shared.store`.
@MainActor
final class KumoAppContext {
    static let shared = KumoAppContext()

    private(set) var store: KumoAppStore?
    private var openMainWindowAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?
    private var openAboutWindowAction: (() -> Void)?

    private init() {}

    func attach(store: KumoAppStore) {
        self.store = store
    }

    func attachWindowActions(
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openAboutWindow: @escaping () -> Void
    ) {
        openMainWindowAction = openMainWindow
        openSettingsAction = openSettings
        openAboutWindowAction = openAboutWindow
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: isMainWindow(_:)) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        openMainWindowAction?()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func openAboutWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "About Kumo" }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        openAboutWindowAction?()
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else {
            return false
        }
        if window.title == "Kumo" {
            return true
        }
        return SidebarDestination.allCases.contains { $0.rawValue == window.title }
    }

    /// Handle a continued `NSUserActivity` (Spotlight tap, Handoff). Returns
    /// `true` when the activity was recognised and dispatched to the store.
    func handleUserActivity(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == "io.kumo.KumoApp.openProfile" else {
            return false
        }
        guard let userInfo = activity.userInfo,
              let identifier = userInfo["profileID"] as? String,
              let store else {
            return false
        }
        store.refreshProfiles()
        if let target = store.profiles.first(where: { $0.id == identifier }) {
            Task { await store.selectProfile(target) }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

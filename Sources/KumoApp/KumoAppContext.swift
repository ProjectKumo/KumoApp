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

    private init() {}

    func attach(store: KumoAppStore) {
        self.store = store
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

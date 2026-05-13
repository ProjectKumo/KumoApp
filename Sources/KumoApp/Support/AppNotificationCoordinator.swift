import Foundation
import KumoCoreKit
import UserNotifications

@MainActor
final class AppNotificationCoordinator {
    static let shared = AppNotificationCoordinator()

    enum CategoryID {
        static let updateAvailable = "UPDATE_AVAILABLE"
        static let updateProgress = "UPDATE_PROGRESS"
        static let restartReady = "RESTART_READY"
    }

    enum ActionID {
        static let startUpdate = "START_UPDATE"
        static let remindLater = "REMIND_LATER"
        static let restartNow = "RESTART_NOW"
    }

    enum RequestID {
        static let updateAvailable = "io.kumo.notification.update.available"
        static let updateProgress = "io.kumo.notification.update.progress"
        static let restartReady = "io.kumo.notification.update.restart"
    }

    enum UserInfoKey {
        static let version = "updateVersion"
        static let channel = "updateChannel"
        static let downloadURL = "downloadURL"
        static let sha256 = "sha256"
        static let releaseNotes = "releaseNotes"
        static let assetName = "assetName"
        static let minimumSystemVersion = "minimumSystemVersion"
    }

    enum UpdateAction {
        case startUpdate
        case remindLater
        case restartNow
        case openApp
    }

    private let center = UNUserNotificationCenter.current()
    private let reminderDefaults = UserDefaults.standard

    private init() {}

    func registerCategories() {
        let startUpdateAction = UNNotificationAction(
            identifier: ActionID.startUpdate,
            title: "Install Now"
        )
        let remindLaterAction = UNNotificationAction(
            identifier: ActionID.remindLater,
            title: "Remind Me Later"
        )
        let restartNowAction = UNNotificationAction(
            identifier: ActionID.restartNow,
            title: "Restart Now"
        )

        let updateAvailableCategory = UNNotificationCategory(
            identifier: CategoryID.updateAvailable,
            actions: [startUpdateAction, remindLaterAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let updateProgressCategory = UNNotificationCategory(
            identifier: CategoryID.updateProgress,
            actions: [startUpdateAction],
            intentIdentifiers: [],
            options: []
        )
        let restartReadyCategory = UNNotificationCategory(
            identifier: CategoryID.restartReady,
            actions: [restartNowAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([updateAvailableCategory, updateProgressCategory, restartReadyCategory])
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // No-op: notifications are optional and the app already has in-app update UI.
        }
    }

    func postUpdateAvailable(manifest: AppUpdateManifest) {
        guard shouldNotifyForVersion(manifest.version) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Update Available"
        content.body = "Kumo \(manifest.version) is ready to install."
        content.sound = .default
        content.categoryIdentifier = CategoryID.updateAvailable
        content.userInfo = userInfo(for: manifest)
        replaceNotification(
            requestID: RequestID.updateAvailable,
            content: content
        )
    }

    func postUpdateProgress(
        manifest: AppUpdateManifest,
        message: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Installing Update"
        content.body = message
        content.sound = nil
        content.categoryIdentifier = CategoryID.updateProgress
        content.userInfo = userInfo(for: manifest)
        replaceNotification(
            requestID: RequestID.updateProgress,
            content: content
        )
    }

    func postRestartReady(manifest: AppUpdateManifest) {
        let content = UNMutableNotificationContent()
        content.title = "Update Installed"
        content.body = "Kumo \(manifest.version) is ready. Restart to finish."
        content.sound = .default
        content.categoryIdentifier = CategoryID.restartReady
        content.userInfo = userInfo(for: manifest)
        replaceNotification(
            requestID: RequestID.restartReady,
            content: content
        )
    }

    func clearUpdateNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [
            RequestID.updateAvailable,
            RequestID.updateProgress,
            RequestID.restartReady
        ])
        center.removeDeliveredNotifications(withIdentifiers: [
            RequestID.updateAvailable,
            RequestID.updateProgress,
            RequestID.restartReady
        ])
    }

    func snoozeReminder(for version: String, hours: Int = 6) {
        let key = reminderKey(for: version)
        let nextDate = Date().addingTimeInterval(TimeInterval(hours) * 3600)
        reminderDefaults.set(nextDate, forKey: key)
    }

    nonisolated static func decodeAction(from actionIdentifier: String) -> UpdateAction {
        switch actionIdentifier {
        case ActionID.startUpdate:
            return .startUpdate
        case ActionID.remindLater:
            return .remindLater
        case ActionID.restartNow:
            return .restartNow
        default:
            return .openApp
        }
    }

    nonisolated static func manifest(from userInfo: [AnyHashable: Any]) -> AppUpdateManifest? {
        guard let version = userInfo[UserInfoKey.version] as? String,
              let rawDownloadURL = userInfo[UserInfoKey.downloadURL] as? String,
              let downloadURL = URL(string: rawDownloadURL) else {
            return nil
        }
        let rawChannel = (userInfo[UserInfoKey.channel] as? String) ?? AppUpdateChannel.stable.rawValue
        let channel = AppUpdateChannel(rawValue: rawChannel) ?? .stable
        return AppUpdateManifest(
            version: version,
            channel: channel,
            downloadURL: downloadURL,
            sha256: userInfo[UserInfoKey.sha256] as? String,
            releaseNotes: userInfo[UserInfoKey.releaseNotes] as? String,
            assetName: userInfo[UserInfoKey.assetName] as? String,
            minimumSystemVersion: userInfo[UserInfoKey.minimumSystemVersion] as? String
        )
    }

    nonisolated static func version(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo[UserInfoKey.version] as? String
    }

    private func shouldNotifyForVersion(_ version: String) -> Bool {
        let key = reminderKey(for: version)
        guard let remindAt = reminderDefaults.object(forKey: key) as? Date else {
            return true
        }
        return remindAt <= Date()
    }

    private func reminderKey(for version: String) -> String {
        "io.kumo.notification.update.reminder.\(version)"
    }

    private func replaceNotification(
        requestID: String,
        content: UNMutableNotificationContent
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        center.add(request)
    }

    private func userInfo(for manifest: AppUpdateManifest) -> [String: Any] {
        var values: [String: Any] = [
            UserInfoKey.version: manifest.version,
            UserInfoKey.channel: manifest.channel.rawValue,
            UserInfoKey.downloadURL: manifest.downloadURL.absoluteString
        ]
        if let sha256 = manifest.sha256 {
            values[UserInfoKey.sha256] = sha256
        }
        if let releaseNotes = manifest.releaseNotes {
            values[UserInfoKey.releaseNotes] = releaseNotes
        }
        if let assetName = manifest.assetName {
            values[UserInfoKey.assetName] = assetName
        }
        if let minimumSystemVersion = manifest.minimumSystemVersion {
            values[UserInfoKey.minimumSystemVersion] = minimumSystemVersion
        }
        return values
    }
}

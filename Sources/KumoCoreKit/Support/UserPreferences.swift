import Foundation

/// User-facing preferences stored separately from runtime `CoreStatus`.
/// These are pure UI/lifecycle preferences that do not change Mihomo's
/// runtime behaviour, so they live in their own file to keep schema
/// migrations cheap.
public struct UserPreferences: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var hideMenuBarIcon: Bool
    public var quitOnLastWindowClose: Bool
    public var updateChannel: AppUpdateChannel
    public var updateManifestURL: URL?

    public init(
        launchAtLogin: Bool = false,
        hideMenuBarIcon: Bool = false,
        quitOnLastWindowClose: Bool = false,
        updateChannel: AppUpdateChannel = .stable,
        updateManifestURL: URL? = nil
    ) {
        self.launchAtLogin = launchAtLogin
        self.hideMenuBarIcon = hideMenuBarIcon
        self.quitOnLastWindowClose = quitOnLastWindowClose
        self.updateChannel = updateChannel
        self.updateManifestURL = updateManifestURL
    }
}

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
    /// Whether the first-run onboarding sheet has already been completed (or
    /// explicitly skipped). The sheet is shown automatically on launch when
    /// this is false, and Settings exposes a way to reopen it.
    public var hasCompletedOnboarding: Bool

    public init(
        launchAtLogin: Bool = false,
        hideMenuBarIcon: Bool = false,
        quitOnLastWindowClose: Bool = false,
        updateChannel: AppUpdateChannel = .stable,
        updateManifestURL: URL? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.hideMenuBarIcon = hideMenuBarIcon
        self.quitOnLastWindowClose = quitOnLastWindowClose
        self.updateChannel = updateChannel
        self.updateManifestURL = updateManifestURL
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case hideMenuBarIcon
        case quitOnLastWindowClose
        case updateChannel
        case updateManifestURL
        case hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserPreferences()
        self.init(
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin,
            hideMenuBarIcon: try container.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon) ?? defaults.hideMenuBarIcon,
            quitOnLastWindowClose: try container.decodeIfPresent(Bool.self, forKey: .quitOnLastWindowClose) ?? defaults.quitOnLastWindowClose,
            updateChannel: try container.decodeIfPresent(AppUpdateChannel.self, forKey: .updateChannel) ?? defaults.updateChannel,
            updateManifestURL: try container.decodeIfPresent(URL.self, forKey: .updateManifestURL),
            hasCompletedOnboarding: try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
        )
    }
}

import Foundation

/// Persists `UserPreferences` as JSON in `Application Support/Kumo/preferences.json`.
/// Decoding falls back to defaults on error so a corrupted/missing file never
/// blocks app launch.
public struct UserPreferencesStore: Sendable {
    private let preferencesFile: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: KumoPaths = KumoPaths()) {
        self.preferencesFile = paths.applicationSupportDirectory.appendingPathComponent("preferences.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> UserPreferences {
        guard FileManager.default.fileExists(atPath: preferencesFile.path) else {
            return UserPreferences()
        }

        do {
            let data = try Data(contentsOf: preferencesFile)
            return try decoder.decode(UserPreferences.self, from: data)
        } catch {
            return UserPreferences()
        }
    }

    public func save(_ preferences: UserPreferences) throws {
        try FileManager.default.createDirectory(
            at: preferencesFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(preferences)
        try data.write(to: preferencesFile, options: .atomic)
    }
}

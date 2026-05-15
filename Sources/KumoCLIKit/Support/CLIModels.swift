import Foundation
import KumoCoreKit

struct ProviderReport: Encodable {
    var proxies: [ProxyProviderEntry]
    var rules: [RuleProviderEntry]
}

struct DoctorReport: Encodable {
    var status: CoreStatus
    var currentProfile: ProfileSummary
    var coreCandidates: [CoreCandidate]
}

public struct CLIPaths: Encodable, Equatable {
    var applicationSupportDirectory: String
    var profilesDirectory: String
    var workDirectory: String
    var logsDirectory: String
    var runtimeConfigFile: String
    var stateFile: String

    init(paths: KumoPaths) {
        self.applicationSupportDirectory = paths.applicationSupportDirectory.path
        self.profilesDirectory = paths.profilesDirectory.path
        self.workDirectory = paths.workDirectory.path
        self.logsDirectory = paths.logsDirectory.path
        self.runtimeConfigFile = paths.runtimeConfigFile.path
        self.stateFile = paths.stateFile.path
    }
}

struct CLILogEntry: Codable, Equatable {
    var createdAt: String
    var level: LogLevel
    var summary: String
}

struct CLILogCleanReport: Codable, Equatable {
    var dryRun: Bool
    var matchedFiles: Int
    var wouldRemoveFiles: Int
}

struct TimingPayload: Encodable {
    var timers: [String: Int]
    var totalMilliseconds: Int
}

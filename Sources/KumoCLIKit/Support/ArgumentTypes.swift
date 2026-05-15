import ArgumentParser
import KumoCoreKit

enum ColorMode: String, ExpressibleByArgument, CaseIterable {
    case always
    case auto
    case never
}

enum ProgressMode: String, ExpressibleByArgument, CaseIterable {
    case `true`
    case `false`
    case auto
}

public enum LogLevel: String, Codable, ExpressibleByArgument, CaseIterable, Comparable {
    case silent
    case error
    case warn
    case notice
    case http
    case info
    case verbose
    case silly

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    func allows(_ level: LogLevel) -> Bool {
        level.rank <= rank && self != .silent
    }

    private var rank: Int {
        switch self {
        case .silent: 0
        case .error: 1
        case .warn: 2
        case .notice: 3
        case .http: 4
        case .info: 5
        case .verbose: 6
        case .silly: 7
        }
    }
}

enum OnOff: String, ExpressibleByArgument {
    case on
    case off
}

enum CompletionShell: String, ExpressibleByArgument {
    case zsh
    case bash
    case fish
}

enum AgentTargetSelection: ExpressibleByArgument {
    case all
    case target(AgentSkillsTarget)

    init?(argument: String) {
        if argument == "all" {
            self = .all
        } else if let target = AgentSkillsTarget(rawValue: argument) {
            self = .target(target)
        } else {
            return nil
        }
    }
}

extension OutboundMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension AgentSkillsScope: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

import Foundation

public enum KumoError: LocalizedError, Equatable {
    case coreNotFound(String)
    case coreAlreadyRunning(Int32)
    case coreNotRunning
    case invalidArguments(String)
    case unsupportedProfileSource
    case controllerResponse(Int, String)
    case commandFailed(String)
    case coreInstallFailed(String)
    case serviceUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .coreNotFound(let path):
            "Mihomo core was not found. Choose a core in Core settings or install mihomo with Homebrew. Last checked: \(path)."
        case .coreAlreadyRunning(let pid):
            "Mihomo core is already running with pid \(pid)."
        case .coreNotRunning:
            "Mihomo core is not running."
        case .invalidArguments(let message):
            message
        case .unsupportedProfileSource:
            "This profile source is not supported yet."
        case .controllerResponse(let status, let body):
            "Controller returned HTTP \(status): \(body)"
        case .commandFailed(let message):
            message
        case .coreInstallFailed(let message):
            "Core installation failed: \(message)"
        case .serviceUnavailable(let message):
            message
        }
    }
}

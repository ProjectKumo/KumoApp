import Darwin
import Foundation

/// The current state of the `kumo` CLI symlink on disk.
public enum CLILinkState: String, Codable, Sendable, Equatable {
    /// The bundled CLI cannot be located, so install cannot proceed.
    case bundledCLIMissing
    /// Nothing exists at the target path yet.
    case notInstalled
    /// A symlink at the target path points to the bundled CLI.
    case installed
    /// A symlink at the target path points to a different CLI (or stale path).
    case differentSymlink
    /// A regular file or other entry occupies the target path.
    case occupiedByOther
}

/// Snapshot of the `kumo` CLI symlink for both UI and CLI surfaces.
public struct CLILinkStatus: Codable, Sendable, Equatable {
    public var state: CLILinkState
    public var targetPath: String
    public var bundledCLIPath: String?
    public var linkResolvedPath: String?
    public var message: String

    public init(
        state: CLILinkState,
        targetPath: String,
        bundledCLIPath: String?,
        linkResolvedPath: String?,
        message: String
    ) {
        self.state = state
        self.targetPath = targetPath
        self.bundledCLIPath = bundledCLIPath
        self.linkResolvedPath = linkResolvedPath
        self.message = message
    }

    public var isInstalled: Bool { state == .installed }
    public var isUpToDate: Bool { state == .installed }
}

/// Manages the symlink that exposes the `kumo` CLI under a stable PATH
/// directory. Install / uninstall require administrator authorization through
/// `osascript` because the default target lives in `/usr/local/bin`, mirroring
/// the pattern used by `KumoServiceManager` for the privileged helper.
public struct CLILinkInstaller: Sendable {
    public static let defaultTargetPath = "/usr/local/bin/kumo"

    public let targetPath: String
    private let explicitBundledCLIPath: String?

    public init(
        targetPath: String = CLILinkInstaller.defaultTargetPath,
        bundledCLIPath: String? = nil
    ) {
        self.targetPath = targetPath
        self.explicitBundledCLIPath = bundledCLIPath
    }

    /// Returns the absolute path to the `kumo` binary that the running app
    /// bundle ships with, or `nil` if it cannot be located. Honors
    /// `KUMO_CLI_PATH` (used by tests and developer overrides) before falling
    /// back to `Bundle.main` lookup.
    public func bundledCLIPath() -> String? {
        if let explicitBundledCLIPath {
            return FileManager.default.isExecutableFile(atPath: explicitBundledCLIPath)
                ? explicitBundledCLIPath
                : nil
        }
        if let environmentPath = ProcessInfo.processInfo.environment["KUMO_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: environmentPath) {
            return environmentPath
        }

        for candidate in Self.bundledCLICandidates() where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    public func status() -> CLILinkStatus {
        let bundled = bundledCLIPath()
        let resolved = symlinkDestination(at: targetPath)

        if let resolved, let bundled, normalize(resolved) == normalize(bundled) {
            return CLILinkStatus(
                state: .installed,
                targetPath: targetPath,
                bundledCLIPath: bundled,
                linkResolvedPath: resolved,
                message: "Installed at \(targetPath)."
            )
        }

        if let resolved {
            return CLILinkStatus(
                state: .differentSymlink,
                targetPath: targetPath,
                bundledCLIPath: bundled,
                linkResolvedPath: resolved,
                message: "A different symlink at \(targetPath) points to \(resolved)."
            )
        }

        if FileManager.default.fileExists(atPath: targetPath) {
            return CLILinkStatus(
                state: .occupiedByOther,
                targetPath: targetPath,
                bundledCLIPath: bundled,
                linkResolvedPath: nil,
                message: "A file already exists at \(targetPath)."
            )
        }

        guard bundled != nil else {
            return CLILinkStatus(
                state: .bundledCLIMissing,
                targetPath: targetPath,
                bundledCLIPath: nil,
                linkResolvedPath: nil,
                message: "Bundled kumo binary is not present in this build."
            )
        }

        return CLILinkStatus(
            state: .notInstalled,
            targetPath: targetPath,
            bundledCLIPath: bundled,
            linkResolvedPath: nil,
            message: "Not installed."
        )
    }

    /// Creates or replaces the `kumo` symlink so it points at the bundled CLI.
    /// Uses administrator authorization for any target that is not writable by
    /// the current user.
    @discardableResult
    public func install(prompt: String = "Install Kumo command-line tool") throws -> CLILinkStatus {
        guard let bundled = bundledCLIPath() else {
            throw KumoError.commandFailed(
                "Bundled kumo binary was not found. Build the Kumo app bundle and try again."
            )
        }

        try ensureTargetDirectoryExists(prompt: prompt)
        try runLink(source: bundled, prompt: prompt)
        return status()
    }

    /// Removes the symlink at the target path, but only when it currently
    /// points at the bundled CLI. Prevents accidentally deleting a user-managed
    /// CLI shim.
    @discardableResult
    public func uninstall(prompt: String = "Remove Kumo command-line tool") throws -> CLILinkStatus {
        let current = status()
        switch current.state {
        case .installed:
            try runRemove(prompt: prompt)
        case .notInstalled, .bundledCLIMissing:
            return current
        case .differentSymlink, .occupiedByOther:
            throw KumoError.commandFailed(
                "Refusing to remove \(targetPath) because it is not managed by Kumo."
            )
        }
        return status()
    }

    /// Returns the directory containing the target path. Useful for callers
    /// that want to surface "is this directory in your PATH" hints.
    public var targetDirectory: String {
        (targetPath as NSString).deletingLastPathComponent
    }

    /// Returns `true` if the target directory is part of the current user's
    /// shell `PATH`. The PATH environment value inherited by GUI apps may
    /// differ from the user's shell PATH, so callers should treat this as a
    /// hint rather than authoritative.
    public func targetDirectoryIsOnPATH() -> Bool {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let entries = pathValue
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        let target = normalize(targetDirectory)
        return entries.contains { normalize($0) == target }
    }

    // MARK: - Private helpers

    private static func bundledCLICandidates() -> [URL] {
        let bundle = Bundle.main
        let bundleURL = bundle.bundleURL
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // The shipping app keeps `kumo` in Contents/Helpers because macOS
        // volumes are case-insensitive by default and Contents/MacOS already
        // hosts the GUI main binary `Kumo`. SwiftPM dev builds expose it
        // under `.build/<config>/kumo` next to the GUI executable.
        let candidates: [URL?] = [
            bundleURL.appendingPathComponent("Contents/Helpers/kumo"),
            workingDirectory.appendingPathComponent(".build/debug/kumo"),
            workingDirectory.appendingPathComponent(".build/release/kumo"),
            workingDirectory.appendingPathComponent("build/Build/Products/Debug/kumo"),
            workingDirectory.appendingPathComponent("build/Build/Products/Release/kumo")
        ]
        return candidates.compactMap { $0 }
    }

    private func symlinkDestination(at path: String) -> String? {
        var statBuffer = stat()
        guard lstat(path, &statBuffer) == 0 else {
            return nil
        }
        guard (statBuffer.st_mode & S_IFMT) == S_IFLNK else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = readlink(path, &buffer, buffer.count - 1)
        guard length > 0 else {
            return nil
        }
        buffer[length] = 0
        return String(cString: buffer)
    }

    private func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func ensureTargetDirectoryExists(prompt: String) throws {
        let directory = targetDirectory
        guard !FileManager.default.fileExists(atPath: directory) else {
            return
        }
        let command = "/bin/mkdir -p \(shellQuote(directory))"
        try runShellCommand(command, prompt: prompt)
    }

    private func runLink(source: String, prompt: String) throws {
        let command = "/bin/ln -sfn \(shellQuote(source)) \(shellQuote(targetPath))"
        try runShellCommand(command, prompt: prompt)
    }

    private func runRemove(prompt: String) throws {
        let command = "/bin/rm -f \(shellQuote(targetPath))"
        try runShellCommand(command, prompt: prompt)
    }

    private func runShellCommand(_ command: String, prompt: String) throws {
        if targetDirectoryIsWritable() {
            try runWithoutAuthorization(command: command)
            return
        }
        try runWithAdministratorAuthorization(command: command, prompt: prompt)
    }

    private func targetDirectoryIsWritable() -> Bool {
        let directory = targetDirectory
        let fileManager = FileManager.default
        if fileManager.isWritableFile(atPath: directory) {
            return true
        }
        // Check if we can create the directory in the parent. If the parent
        // is writable we can also `mkdir` without sudo.
        let parent = (directory as NSString).deletingLastPathComponent
        guard !parent.isEmpty,
              fileManager.fileExists(atPath: parent),
              fileManager.isWritableFile(atPath: parent) else {
            return false
        }
        return true
    }

    private func runWithoutAuthorization(command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func runWithAdministratorAuthorization(command: String, prompt: String) throws {
        if geteuid() == 0 {
            try runWithoutAuthorization(command: command)
            return
        }
        let script = #"do shell script "\#(appleScriptQuote(command))" with administrator privileges with prompt "\#(appleScriptQuote(prompt))""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

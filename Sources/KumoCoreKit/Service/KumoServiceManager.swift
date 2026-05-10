import Darwin
import Foundation

public struct KumoServiceManager: Sendable {
    public static let launchDaemonLabel = "io.kumo.KumoService"

    private let paths: KumoPaths

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
    }

    public func status() -> ServiceModeStatus {
        let isPrivileged = geteuid() == 0
        let socketPath = paths.serviceSocketFile.path
        let socketExists = FileManager.default.fileExists(atPath: socketPath)
        let installed = FileManager.default.fileExists(atPath: paths.serviceLaunchDaemonPlistFile.path)
            || FileManager.default.fileExists(atPath: paths.serviceExecutableFile.path)
            || savedInstalledFlag()
        let running = isPrivileged ? socketExists : serviceClient()?.ping() == true
        let available = running || isPrivileged

        return ServiceModeStatus(
            isInstalled: installed,
            isRunning: running,
            isAvailable: available,
            isCurrentProcessPrivileged: isPrivileged,
            socketPath: socketPath,
            message: statusMessage(isInstalled: installed, isRunning: running, isPrivileged: isPrivileged)
        )
    }

    @discardableResult
    public func installService() throws -> ServiceModeStatus {
        let credentials = try ensureCredentials()
        let source = try helperExecutableCandidate()
        let arguments = [
            "service",
            "install",
            "--source", source.path,
            "--app-support", paths.applicationSupportDirectory.path,
            "--authorized-uid", "\(getuid())",
            "--key-id", credentials.keyID,
            "--shared-secret", credentials.sharedSecret
        ]
        try runServiceCommandWithAuthorization(executable: source.path, arguments: arguments, prompt: "Install Kumo Helper")
        let status = status()
        try saveInstalledFlag(status)
        return status
    }

    @discardableResult
    public func uninstallService() throws -> ServiceModeStatus {
        let executable = FileManager.default.isExecutableFile(atPath: paths.serviceExecutableFile.path)
            ? paths.serviceExecutableFile
            : try helperExecutableCandidate()
        try runServiceCommandWithAuthorization(
            executable: executable.path,
            arguments: ["service", "uninstall", "--app-support", paths.applicationSupportDirectory.path],
            prompt: "Uninstall Kumo Helper"
        )
        try? FileManager.default.removeItem(at: paths.serviceCredentialsFile)
        let next = status()
        try saveInstalledFlag(next)
        return next
    }

    public func serviceClient() -> KumoServiceClient? {
        guard let credentials = try? loadCredentials() else {
            return nil
        }
        return KumoServiceClient(
            endpoint: KumoServiceEndpoint(socketPath: paths.serviceSocketFile.path),
            credentials: credentials
        )
    }

    public func ensureCredentials() throws -> KumoServiceCredentials {
        if let credentials = try? loadCredentials() {
            return credentials
        }
        let credentials = KumoServiceCredentials(
            keyID: UUID().uuidString,
            sharedSecret: UUID().uuidString + UUID().uuidString
        )
        try FileManager.default.createDirectory(
            at: paths.serviceCredentialsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(credentials).write(to: paths.serviceCredentialsFile, options: .atomic)
        chmod(paths.serviceCredentialsFile.path, S_IRUSR | S_IWUSR)
        return credentials
    }

    public func loadCredentials() throws -> KumoServiceCredentials {
        let data = try Data(contentsOf: paths.serviceCredentialsFile)
        return try JSONDecoder().decode(KumoServiceCredentials.self, from: data)
    }

    private func savedInstalledFlag() -> Bool {
        guard let data = try? Data(contentsOf: paths.serviceStatusFile),
              let object = try? JSONDecoder().decode(ServiceModeStatus.self, from: data) else {
            return false
        }
        return object.isInstalled
    }

    private func saveInstalledFlag(_ status: ServiceModeStatus) throws {
        try FileManager.default.createDirectory(
            at: paths.serviceStatusFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(status).write(to: paths.serviceStatusFile, options: .atomic)
    }

    private func statusMessage(isInstalled: Bool, isRunning: Bool, isPrivileged: Bool) -> String? {
        if isRunning {
            return "Kumo Helper is running. System proxy service mode and TUN can use the privileged backend."
        }
        if isPrivileged {
            return "Current process is privileged. TUN can run without the helper, but installing Kumo Helper is recommended."
        }
        if isInstalled {
            return "Kumo Helper is installed but not reachable. Use Install / Repair Service to reload it."
        }
        return "TUN requires Kumo Helper or a privileged Kumo process. Installing the helper shows a macOS administrator authorization prompt, not a VPN configuration prompt."
    }

    private func helperExecutableCandidate() throws -> URL {
        let bundle = Bundle.main
        let executableDirectory = bundle.executableURL?.deletingLastPathComponent()
        let productDirectory = bundle.bundleURL.deletingLastPathComponent()
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            bundle.bundleURL.appendingPathComponent("Contents/MacOS/KumoService"),
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/KumoService"),
            productDirectory.appendingPathComponent("KumoService"),
            executableDirectory?.appendingPathComponent("KumoService"),
            workingDirectory.appendingPathComponent("KumoService"),
            workingDirectory.appendingPathComponent(".build/debug/KumoService"),
            workingDirectory.appendingPathComponent(".build/release/KumoService"),
            workingDirectory.appendingPathComponent("build/Build/Products/Debug/KumoService"),
            workingDirectory.appendingPathComponent("build/Build/Products/Release/KumoService"),
            paths.serviceExecutableFile
        ].compactMap { $0 }

        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }

        throw KumoError.serviceUnavailable(
            "KumoService executable was not found. Build or bundle KumoService before installing the helper."
        )
    }

    private func runServiceCommandWithAuthorization(
        executable: String,
        arguments: [String],
        prompt: String
    ) throws {
        if geteuid() == 0 {
            try run(executable: executable, arguments: arguments)
            return
        }

        let command = ([executable] + arguments).map(shellQuote).joined(separator: " ")
        let script = #"do shell script "\#(appleScriptQuote(command))" with administrator privileges with prompt "\#(appleScriptQuote(prompt))""#
        try run(executable: "/usr/bin/osascript", arguments: ["-e", script])
    }

    private func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.serviceUnavailable(output.trimmingCharacters(in: .whitespacesAndNewlines))
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

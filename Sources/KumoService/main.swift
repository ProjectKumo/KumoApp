import Darwin
import Foundation
import KumoCoreKit

@main
enum KumoServiceMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard arguments.first == "service" else {
            print("Usage: KumoService service <install|uninstall|status|run>")
            return
        }
        let command = arguments.dropFirst().first ?? "status"
        let remaining = Array(arguments.dropFirst(2))
        switch command {
        case "install":
            try install(arguments: remaining)
        case "uninstall":
            try uninstall(arguments: remaining)
        case "status":
            try printStatus(arguments: remaining)
        case "run":
            try await runDaemon(arguments: remaining)
        default:
            throw KumoError.invalidArguments("Unknown service command: \(command)")
        }
    }

    private static func install(arguments: [String]) throws {
        guard geteuid() == 0 else {
            throw KumoError.serviceUnavailable("KumoService install must run with administrator privileges.")
        }
        guard let source = value(after: "--source", in: arguments),
              let appSupport = value(after: "--app-support", in: arguments),
              let authorizedUID = value(after: "--authorized-uid", in: arguments).flatMap(uid_t.init),
              let keyID = value(after: "--key-id", in: arguments),
              let sharedSecret = value(after: "--shared-secret", in: arguments) else {
            throw KumoError.invalidArguments("Usage: KumoService service install --source <path> --app-support <path> --authorized-uid <uid> --key-id <id> --shared-secret <secret>")
        }

        let paths = KumoPaths(applicationSupportDirectory: URL(fileURLWithPath: appSupport, isDirectory: true))
        try paths.prepare()
        try FileManager.default.createDirectory(
            at: paths.serviceExecutableFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if source != paths.serviceExecutableFile.path,
           FileManager.default.fileExists(atPath: paths.serviceExecutableFile.path) {
            try FileManager.default.removeItem(at: paths.serviceExecutableFile)
        }
        if source != paths.serviceExecutableFile.path {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: paths.serviceExecutableFile)
        }
        chmod(paths.serviceExecutableFile.path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)
        chown(paths.serviceExecutableFile.path, 0, 0)

        let credentials = KumoServiceCredentials(keyID: keyID, sharedSecret: sharedSecret)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(credentials).write(to: paths.serviceCredentialsFile, options: .atomic)
        chown(paths.serviceCredentialsFile.path, authorizedUID, getgid())
        chmod(paths.serviceCredentialsFile.path, S_IRUSR | S_IWUSR)

        let plist = launchDaemonPlist(paths: paths, authorizedUID: authorizedUID)
        try plist.write(to: paths.serviceLaunchDaemonPlistFile, atomically: true, encoding: .utf8)
        chown(paths.serviceLaunchDaemonPlistFile.path, 0, 0)
        chmod(paths.serviceLaunchDaemonPlistFile.path, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)

        _ = try? runCommand("/bin/launchctl", ["bootout", "system/\(KumoServiceManager.launchDaemonLabel)"])
        try runCommand("/bin/launchctl", ["bootstrap", "system", paths.serviceLaunchDaemonPlistFile.path])
        _ = try? runCommand("/bin/launchctl", ["kickstart", "-k", "system/\(KumoServiceManager.launchDaemonLabel)"])
        try saveStatus(paths: paths, installed: true, running: false)
    }

    private static func uninstall(arguments: [String]) throws {
        guard geteuid() == 0 else {
            throw KumoError.serviceUnavailable("KumoService uninstall must run with administrator privileges.")
        }
        let appSupport = value(after: "--app-support", in: arguments)
        let paths = KumoPaths(applicationSupportDirectory: appSupport.map { URL(fileURLWithPath: $0, isDirectory: true) })
        _ = try? runCommand("/bin/launchctl", ["bootout", "system/\(KumoServiceManager.launchDaemonLabel)"])
        try? FileManager.default.removeItem(at: paths.serviceLaunchDaemonPlistFile)
        try? FileManager.default.removeItem(at: paths.serviceExecutableFile)
        try? FileManager.default.removeItem(at: paths.serviceSocketFile)
        try saveStatus(paths: paths, installed: false, running: false)
    }

    private static func printStatus(arguments: [String]) throws {
        let appSupport = value(after: "--app-support", in: arguments)
        let paths = KumoPaths(applicationSupportDirectory: appSupport.map { URL(fileURLWithPath: $0, isDirectory: true) })
        let status = ServiceModeStatus(
            isInstalled: FileManager.default.fileExists(atPath: paths.serviceLaunchDaemonPlistFile.path),
            isRunning: FileManager.default.fileExists(atPath: paths.serviceSocketFile.path),
            isAvailable: geteuid() == 0 || FileManager.default.fileExists(atPath: paths.serviceSocketFile.path),
            isCurrentProcessPrivileged: geteuid() == 0,
            socketPath: paths.serviceSocketFile.path
        )
        let data = try JSONEncoder().encode(status)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func runDaemon(arguments: [String]) async throws {
        guard let appSupport = value(after: "--app-support", in: arguments) else {
            throw KumoError.invalidArguments("KumoService service run requires --app-support <path>.")
        }
        let authorizedUID = value(after: "--authorized-uid", in: arguments).flatMap(uid_t.init) ?? getuid()
        let paths = KumoPaths(applicationSupportDirectory: URL(fileURLWithPath: appSupport, isDirectory: true))
        try paths.prepare()
        let credentials = try KumoServiceManager(paths: paths).loadCredentials()
        let server = KumoServiceSocketServer(paths: paths, credentials: credentials, authorizedUID: authorizedUID)
        try await server.run()
    }

    private static func launchDaemonPlist(paths: KumoPaths, authorizedUID: uid_t) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(KumoServiceManager.launchDaemonLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(paths.serviceExecutableFile.path)</string>
            <string>service</string>
            <string>run</string>
            <string>--app-support</string>
            <string>\(paths.applicationSupportDirectory.path)</string>
            <string>--authorized-uid</string>
            <string>\(authorizedUID)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(paths.serviceLogFile.path)</string>
          <key>StandardErrorPath</key>
          <string>\(paths.serviceLogFile.path)</string>
        </dict>
        </plist>
        """
    }

    fileprivate static func saveStatus(paths: KumoPaths, installed: Bool, running: Bool) throws {
        let status = ServiceModeStatus(
            isInstalled: installed,
            isRunning: running,
            isAvailable: running || geteuid() == 0,
            isCurrentProcessPrivileged: geteuid() == 0,
            socketPath: paths.serviceSocketFile.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(status).write(to: paths.serviceStatusFile, options: .atomic)
    }

    @discardableResult
    private static func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw KumoError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }
}

private final class KumoServiceSocketServer: @unchecked Sendable {
    private let paths: KumoPaths
    private let credentials: KumoServiceCredentials
    private let authorizedUID: uid_t
    private var seenNonces = Set<String>()

    init(paths: KumoPaths, credentials: KumoServiceCredentials, authorizedUID: uid_t) {
        self.paths = paths
        self.credentials = credentials
        self.authorizedUID = authorizedUID
    }

    func run() async throws {
        try? FileManager.default.removeItem(at: paths.serviceSocketFile)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw KumoError.serviceUnavailable("Unable to create service socket.")
        }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let socketPath = paths.serviceSocketFile.path
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < maxPathLength else {
            throw KumoError.serviceUnavailable("Service socket path is too long: \(socketPath)")
        }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { buffer in
                socketPath.withCString { source in
                    strncpy(buffer, source, maxPathLength - 1)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw KumoError.serviceUnavailable("Unable to bind service socket at \(socketPath).")
        }
        chmod(socketPath, S_IRUSR | S_IWUSR)
        chown(socketPath, authorizedUID, getgid())

        guard listen(descriptor, 16) == 0 else {
            throw KumoError.serviceUnavailable("Unable to listen on service socket.")
        }
        try KumoServiceMain.saveStatus(paths: paths, installed: true, running: true)

        while true {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { continue }
            let response = await handleConnection(client)
            try? writeResponse(response, to: client)
            close(client)
        }
    }

    private func handleConnection(_ descriptor: Int32) async -> KumoServiceTransportResponse {
        do {
            let data = try readAll(from: descriptor)
            let transport = try JSONDecoder().decode(KumoServiceTransportRequest.self, from: data)
            let request = transport.signedRequest
            guard KumoServiceRequestSigner.validate(request, credentials: credentials, seenNonces: &seenNonces) else {
                return KumoServiceTransportResponse(status: 401, error: "Invalid Kumo service signature.")
            }
            return try await route(request)
        } catch {
            return KumoServiceTransportResponse(status: 500, error: error.localizedDescription)
        }
    }

    private func route(_ request: KumoServiceSignedRequest) async throws -> KumoServiceTransportResponse {
        let controller = KumoController(paths: paths, useServiceBackend: false)
        switch (request.method, request.path) {
        case ("GET", "/service/status"):
            return try json(ServiceModeStatus(
                isInstalled: true,
                isRunning: true,
                isAvailable: true,
                isCurrentProcessPrivileged: geteuid() == 0,
                socketPath: paths.serviceSocketFile.path,
                message: "Kumo Helper is running."
            ))
        case ("GET", "/status"), ("GET", "/sysproxy/status"):
            return try json(controller.status())
        case ("POST", "/core/start"):
            return try json(controller.start())
        case ("POST", "/core/stop"):
            return try json(controller.stop())
        case ("POST", "/core/restart"):
            return try json(controller.restart())
        case ("POST", "/sysproxy/enable"):
            _ = try await controller.setSystemProxy(true)
            return try json(controller.status())
        case ("POST", "/sysproxy/disable"):
            _ = try await controller.setSystemProxy(false)
            return try json(controller.status())
        case ("GET", "/tun/status"):
            return try json(controller.tunStatus())
        case ("POST", "/tun/enable"):
            return try json(try await controller.setTunEnabled(true))
        case ("POST", "/tun/disable"):
            return try json(try await controller.setTunEnabled(false))
        case ("POST", "/tun/settings"):
            let settings = try JSONDecoder().decode(TunSettings.self, from: request.body)
            return try json(try await controller.applyTunSettings(settings))
        default:
            return KumoServiceTransportResponse(status: 404, error: "Unknown Kumo service endpoint: \(request.method) \(request.path)")
        }
    }

    private func json<T: Encodable>(_ value: T) throws -> KumoServiceTransportResponse {
        KumoServiceTransportResponse(status: 200, body: try JSONEncoder().encode(value))
    }

    private func readAll(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 {
                return data
            }
            guard count > 0 else {
                throw KumoError.serviceUnavailable("Failed to read service request.")
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private func writeResponse(_ response: KumoServiceTransportResponse, to descriptor: Int32) throws {
        let data = try JSONEncoder().encode(response)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesWritten = 0
            while bytesWritten < data.count {
                let result = Darwin.write(descriptor, baseAddress.advanced(by: bytesWritten), data.count - bytesWritten)
                guard result > 0 else {
                    throw KumoError.serviceUnavailable("Failed to write service response.")
                }
                bytesWritten += result
            }
        }
    }
}

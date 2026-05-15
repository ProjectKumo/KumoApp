import Darwin
import Foundation
import XCTest
@testable import KumoCoreKit

final class CoreSupervisorTests: XCTestCase {
    func testStartWritesPIDFileAndStopTerminatesProcess() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let corePath = try makeLongRunningCore(in: paths.applicationSupportDirectory)
        let supervisor = CoreSupervisor(paths: paths)

        let status = try supervisor.start(configuration: launchConfiguration(corePath: corePath))
        let pid = try XCTUnwrap(status.pid)

        XCTAssertEqual(try String(contentsOf: paths.corePIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "\(pid)")

        let stopped = try supervisor.stop()

        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertNil(stopped.pid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.corePIDFile.path))
        XCTAssertFalse(isProcessAlive(pid))
    }

    func testStopUsesPIDFileWhenStatePIDIsMissing() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let corePath = try makeLongRunningCore(in: paths.applicationSupportDirectory)
        let supervisor = CoreSupervisor(paths: paths)
        let stateStore = CoreStateStore(paths: paths)

        let status = try supervisor.start(configuration: launchConfiguration(corePath: corePath))
        let pid = try XCTUnwrap(status.pid)
        try stateStore.save(CoreStatus(corePath: corePath))

        let stopped = try supervisor.stop()

        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertNil(stopped.pid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.corePIDFile.path))
        XCTAssertFalse(isProcessAlive(pid))
    }

    func testStatusRecoversRunningPIDFromPIDFileWhenStatePIDIsMissing() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let corePath = try makeLongRunningCore(in: paths.applicationSupportDirectory)
        let supervisor = CoreSupervisor(paths: paths)
        let stateStore = CoreStateStore(paths: paths)

        let status = try supervisor.start(configuration: launchConfiguration(corePath: corePath))
        let pid = try XCTUnwrap(status.pid)
        try stateStore.save(CoreStatus(corePath: corePath))

        let recovered = try supervisor.status()

        XCTAssertEqual(recovered.state, .running)
        XCTAssertEqual(recovered.pid, pid)
        _ = try supervisor.stop()
    }

    func testStartPassesControllerEndpointToMihomoArguments() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let argumentsFile = paths.applicationSupportDirectory.appendingPathComponent("core-arguments.txt")
        let corePath = try makeLongRunningCore(in: paths.applicationSupportDirectory, recordedArgumentsURL: argumentsFile)
        let supervisor = CoreSupervisor(paths: paths)

        let status = try supervisor.start(
            configuration: launchConfiguration(
                corePath: corePath,
                endpoint: ControllerEndpoint(port: 19097, secret: "test-secret")
            )
        )
        defer { _ = try? supervisor.stop() }

        XCTAssertEqual(status.endpoint.port, 19097)
        XCTAssertEqual(
            try recordedArguments(at: argumentsFile),
            [
                "-d",
                paths.workDirectory.path,
                "-ext-ctl",
                "127.0.0.1:19097",
                "-secret",
                "test-secret"
            ]
        )
    }

    private func launchConfiguration(
        corePath: String,
        endpoint: ControllerEndpoint = ControllerEndpoint()
    ) -> CoreLaunchConfiguration {
        CoreLaunchConfiguration(
            corePath: corePath,
            profile: Profile(
                name: "Test",
                source: .inline,
                rawYAML: """
                proxies: []
                proxy-groups:
                  - name: Proxy
                    type: select
                    proxies:
                      - DIRECT
                rules:
                  - MATCH,DIRECT
                """
            ),
            endpoint: endpoint
        )
    }

    private func makeLongRunningCore(in directory: URL, recordedArgumentsURL: URL? = nil) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-mihomo")
        let script: String
        if let recordedArgumentsURL {
            let escapedPath = recordedArgumentsURL.path.replacingOccurrences(of: "'", with: "'\\''")
            script = """
            #!/bin/sh
            printf '%s\\n' "$@" > '\(escapedPath)'
            exec /bin/sleep 600
            """
        } else {
            script = """
            #!/bin/sh
            exec /bin/sleep 600
            """
        }
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func recordedArguments(at url: URL) throws -> [String] {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return try String(contentsOf: url, encoding: .utf8)
                    .split(separator: "\n")
                    .map(String.init)
            }
            usleep(50_000)
        }

        XCTFail("Timed out waiting for recorded core arguments")
        return []
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0
    }
}

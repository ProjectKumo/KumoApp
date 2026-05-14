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

    private func launchConfiguration(corePath: String) -> CoreLaunchConfiguration {
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
            )
        )
    }

    private func makeLongRunningCore(in directory: URL) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        exec /bin/sleep 600
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0
    }
}

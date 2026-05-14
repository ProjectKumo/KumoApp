import Darwin
import Foundation
import XCTest
@testable import KumoCoreKit

final class KumoControllerShutdownTests: XCTestCase {
    func testShutdownActiveRuntimeStopsRunningCore() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = KumoController(paths: paths)
        let corePath = try makeLongRunningCore(in: paths.applicationSupportDirectory)
        let running = try controller.start(corePath: corePath)
        let pid = try XCTUnwrap(running.pid)

        let result = await controller.shutdownActiveRuntime()

        XCTAssertEqual(result.status.state, .stopped)
        XCTAssertNil(result.status.pid)
        XCTAssertFalse(isProcessAlive(pid))
        XCTAssertTrue(result.diagnostics.isEmpty, "unexpected diagnostics: \(result.diagnostics)")
    }

    func testShutdownActiveRuntimeDoesNotMutateStoppedTunPreference() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = KumoController(paths: paths)
        let stateStore = CoreStateStore(paths: paths)
        try stateStore.save(CoreStatus(
            runtimeSettings: CoreRuntimeSettings(tun: TunSettings(isEnabled: true)),
            tunStatus: TunStatus(isEnabled: true, isRunning: false, requiresService: false)
        ))

        let result = await controller.shutdownActiveRuntime()

        XCTAssertEqual(result.status.state, .stopped)
        XCTAssertTrue(result.status.runtimeSettings?.tun?.isEnabled ?? false)
    }

    func testShutdownActiveRuntimeDisablesSystemProxy() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let stateStore = CoreStateStore(paths: paths)
        try stateStore.save(CoreStatus(
            systemProxyEnabled: true,
            systemProxySettings: SystemProxySettings(networkService: "Wi-Fi")
        ))

        let recorder = RecordingCommandRunner()
        // `setSystemProxy(false)` ends with `verifyAppliedState`, which reads
        // each proxy state via `networksetup -get…` and requires the output
        // to contain "Enabled: No" before considering the disable applied.
        recorder.stubCapture(for: "/usr/sbin/networksetup", with: "Enabled: No\nServer:\nPort: 0\n")
        let controller = KumoController(
            paths: paths,
            systemProxyCommandRunner: recorder.makeRunner()
        )

        let result = await controller.shutdownActiveRuntime()

        XCTAssertTrue(result.diagnostics.isEmpty, "unexpected diagnostics: \(result.diagnostics)")
        XCTAssertFalse(result.status.systemProxyEnabled)
        let runArgs = recorder.runArguments()
        XCTAssertTrue(
            runArgs.contains(["-setwebproxystate", "Wi-Fi", "off"]),
            "expected web proxy disable; ran: \(runArgs)"
        )
        XCTAssertTrue(
            runArgs.contains(["-setsecurewebproxystate", "Wi-Fi", "off"]),
            "expected secure web proxy disable; ran: \(runArgs)"
        )
        XCTAssertTrue(
            runArgs.contains(["-setsocksfirewallproxystate", "Wi-Fi", "off"]),
            "expected SOCKS proxy disable; ran: \(runArgs)"
        )
        XCTAssertTrue(
            runArgs.contains(["-setautoproxystate", "Wi-Fi", "off"]),
            "expected PAC autoproxy disable; ran: \(runArgs)"
        )
    }

    func testShutdownActiveRuntimeCollectsBothProxyErrors() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let stateStore = CoreStateStore(paths: paths)
        try stateStore.save(CoreStatus(
            systemProxyEnabled: true,
            systemProxySettings: SystemProxySettings(networkService: "Wi-Fi")
        ))

        let recorder = RecordingCommandRunner()
        recorder.runError = KumoError.commandFailed("simulated networksetup failure")
        recorder.stubCapture(for: "/usr/sbin/networksetup", with: "")
        let controller = KumoController(
            paths: paths,
            systemProxyCommandRunner: recorder.makeRunner()
        )

        let result = await controller.shutdownActiveRuntime()

        XCTAssertEqual(
            result.diagnostics.count, 2,
            "expected both system-proxy stages to report a diagnostic; got: \(result.diagnostics)"
        )
        XCTAssertTrue(
            result.diagnostics[0].hasPrefix("system-proxy:"),
            "first diagnostic should be the helper/async path; got: \(result.diagnostics)"
        )
        XCTAssertTrue(
            result.diagnostics[1].hasPrefix("system-proxy-fallback:"),
            "second diagnostic should be the synchronous fallback; got: \(result.diagnostics)"
        )
    }

    func testShutdownActiveRuntimeIsNoOpWhenAlreadyStopped() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let stateStore = CoreStateStore(paths: paths)
        try stateStore.save(CoreStatus(state: .stopped, pid: nil, systemProxyEnabled: false))

        let recorder = RecordingCommandRunner()
        let controller = KumoController(
            paths: paths,
            systemProxyCommandRunner: recorder.makeRunner()
        )

        let result = await controller.shutdownActiveRuntime()

        XCTAssertTrue(result.diagnostics.isEmpty, "unexpected diagnostics: \(result.diagnostics)")
        XCTAssertEqual(result.status.state, .stopped)
        XCTAssertNil(result.status.pid)
        XCTAssertTrue(recorder.runArguments().isEmpty, "no commands should have run; ran: \(recorder.runArguments())")
    }

    func testDisableSynchronouslyClearsPersistedState() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let stateStore = CoreStateStore(paths: paths)
        try stateStore.save(CoreStatus(
            systemProxyEnabled: true,
            systemProxySettings: SystemProxySettings(networkService: "Wi-Fi"),
            previousSystemProxySnapshot: SystemProxySnapshot(networkService: "Wi-Fi")
        ))

        let recorder = RecordingCommandRunner()
        let controller = SystemProxyController(paths: paths, commandRunner: recorder.makeRunner())

        let commands = try controller.disableSynchronously(
            configuration: SystemProxyConfiguration(networkService: "Wi-Fi")
        )

        XCTAssertFalse(commands.isEmpty)
        let stored = try stateStore.load()
        XCTAssertFalse(stored.systemProxyEnabled)
        XCTAssertNil(stored.previousSystemProxySnapshot)

        let runArgs = recorder.runArguments()
        XCTAssertTrue(runArgs.contains(["-setwebproxystate", "Wi-Fi", "off"]))
        XCTAssertTrue(runArgs.contains(["-setautoproxystate", "Wi-Fi", "off"]))
    }

    // MARK: - Helpers

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

/// Records every command issued through a `SystemProxyCommandRunner` and
/// optionally fails them with a configured error. Access is guarded by an
/// NSLock so the closures are safe to call from any executor — the public
/// surface looks ordinary but mutation is mediated.
private final class RecordingCommandRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var _ranCommands: [ShellCommand] = []
    private var _capturedCommands: [ShellCommand] = []
    private var _captureStubs: [String: String] = [:]
    private var _runError: Error?

    var runError: Error? {
        get { lock.lock(); defer { lock.unlock() }; return _runError }
        set { lock.lock(); _runError = newValue; lock.unlock() }
    }

    func stubCapture(for executable: String, with output: String) {
        lock.lock()
        _captureStubs[executable] = output
        lock.unlock()
    }

    func runArguments() -> [[String]] {
        lock.lock(); defer { lock.unlock() }
        return _ranCommands.map { $0.arguments }
    }

    func makeRunner() -> SystemProxyCommandRunner {
        SystemProxyCommandRunner(
            run: { [self] command in
                self.lock.lock()
                self._ranCommands.append(command)
                let error = self._runError
                self.lock.unlock()
                if let error { throw error }
            },
            captureOutput: { [self] command in
                self.lock.lock()
                self._capturedCommands.append(command)
                let stub = self._captureStubs[command.executable] ?? ""
                self.lock.unlock()
                return stub
            }
        )
    }
}

import XCTest
@testable import KumoCLIKit
import KumoCoreKit

final class KumoCLIKitTests: XCTestCase {
    func testCLIResponseEncodesStableEnvelopeKeysWithNulls() throws {
        let response = CLIResponse<String>(ok: false, error: "boom")
        let data = try JSONEncoder().encode(response)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["ok"] as? Bool, false)
        XCTAssertTrue(object.keys.contains("data"))
        XCTAssertTrue(object.keys.contains("error"))
        XCTAssertTrue(object["data"] is NSNull)
        XCTAssertEqual(object["error"] as? String, "boom")
    }

    func testTopLevelHelpUsesNPMStylePrompts() {
        XCTAssertTrue(HelpText.topLevel.contains("kumo <command> -h"))
        XCTAssertTrue(HelpText.topLevel.contains("kumo -l"))
        XCTAssertTrue(HelpText.topLevel.contains("kumo help <term>"))
        XCTAssertTrue(HelpText.topLevel.contains("All commands:"))
    }

    func testJSONHelpDocumentsEnvelopeAndExitCodes() {
        let help = HelpText.topic(["json"])

        XCTAssertTrue(help.contains("\"ok\": true"))
        XCTAssertTrue(help.contains("\"error\": null"))
        XCTAssertTrue(help.contains("Exit code 0 means success. Exit code 1 means failure."))
    }

    func testArgumentParserAcceptsExpectedAliasesAndRejectsBadMode() throws {
        XCTAssertNoThrow(try KumoCommand.parseAsRoot(["st", "--json"]))
        XCTAssertNoThrow(try KumoCommand.parseAsRoot(["proxy", "--json"]))
        XCTAssertThrowsError(try KumoCommand.parseAsRoot(["mode", "auto", "--json"]))
    }

    func testRendererDisablesColorForJSON() {
        let renderer = OutputRenderer(options: RuntimeOptions(arguments: ["status", "--json", "--color", "always"]))

        XCTAssertFalse(renderer.usesColor)
        XCTAssertEqual(renderer.error("[error] boom"), "[error] boom")
    }

    func testLogRedactorRemovesSecrets() {
        let input = "Authorization: Bearer abc secret=def token=ghi https://user:pass@example.com/path"
        let output = LogRedactor.redact(input)

        XCTAssertFalse(output.contains("abc"))
        XCTAssertFalse(output.contains("def"))
        XCTAssertFalse(output.contains("ghi"))
        XCTAssertFalse(output.contains("pass@example.com"))
        XCTAssertTrue(output.contains("[redacted]"))
    }

    func testDebugLogStoreCleanSupportsDryRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = KumoPaths(applicationSupportDirectory: root)
        let options = RuntimeOptions(arguments: ["--logs-max", "1"])
        let store = DebugLogStore(paths: paths, options: options)

        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: store.directory.appendingPathComponent("2026-a-kumo-debug-0.log"))
        try Data("two".utf8).write(to: store.directory.appendingPathComponent("2026-b-kumo-debug-0.log"))

        let report = try store.clean(dryRun: true)

        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(report.matchedFiles, 2)
        XCTAssertEqual(report.wouldRemoveFiles, 1)
    }
}

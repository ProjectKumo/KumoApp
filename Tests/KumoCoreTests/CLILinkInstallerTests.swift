import Darwin
import XCTest
@testable import KumoCoreKit

final class CLILinkInstallerTests: XCTestCase {
    func testStatusReportsBundledCLIMissingWhenSourceAndTargetAreMissing() throws {
        let fixture = try makeFixture()
        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.missingBundledPath
        )

        let status = installer.status()
        XCTAssertEqual(status.state, .bundledCLIMissing)
        XCTAssertEqual(status.targetPath, fixture.targetPath)
        XCTAssertNil(status.bundledCLIPath)
        XCTAssertNil(status.linkResolvedPath)
    }

    func testStatusReportsNotInstalledWhenSourceExistsButTargetMissing() throws {
        let fixture = try makeFixture()
        try fixture.writeBundledCLI()
        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.bundledPath
        )

        let status = installer.status()
        XCTAssertEqual(status.state, .notInstalled)
        XCTAssertEqual(status.bundledCLIPath, fixture.bundledPath)
        XCTAssertNil(status.linkResolvedPath)
    }

    func testInstallCreatesSymlinkAndStatusReportsInstalled() throws {
        let fixture = try makeFixture()
        try fixture.writeBundledCLI()
        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.bundledPath
        )

        let status = try installer.install(prompt: "test")
        XCTAssertEqual(status.state, .installed)
        XCTAssertEqual(status.linkResolvedPath, fixture.bundledPath)

        let refreshed = installer.status()
        XCTAssertEqual(refreshed.state, .installed)
        XCTAssertTrue(refreshed.isInstalled)
    }

    func testInstallReplacesExistingSymlinkPointingElsewhere() throws {
        let fixture = try makeFixture()
        try fixture.writeBundledCLI()
        let otherSource = fixture.scratch.appendingPathComponent("other-kumo").path
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: otherSource))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: otherSource)
        try fixture.makeSymlink(from: otherSource)

        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.bundledPath
        )

        let beforeInstall = installer.status()
        XCTAssertEqual(beforeInstall.state, .differentSymlink)
        XCTAssertEqual(beforeInstall.linkResolvedPath, otherSource)

        let status = try installer.install(prompt: "test")
        XCTAssertEqual(status.state, .installed)
        XCTAssertEqual(status.linkResolvedPath, fixture.bundledPath)
    }

    func testStatusReportsOccupiedByOtherWhenTargetIsRegularFile() throws {
        let fixture = try makeFixture()
        try fixture.writeBundledCLI()
        try Data("not a symlink".utf8).write(to: URL(fileURLWithPath: fixture.targetPath))
        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.bundledPath
        )

        let status = installer.status()
        XCTAssertEqual(status.state, .occupiedByOther)
        XCTAssertNil(status.linkResolvedPath)
    }

    func testUninstallRemovesInstalledSymlink() throws {
        let fixture = try makeFixture()
        try fixture.writeBundledCLI()
        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.bundledPath
        )
        _ = try installer.install(prompt: "test")

        let status = try installer.uninstall(prompt: "test")
        XCTAssertEqual(status.state, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetPath))
    }

    func testUninstallRefusesToTouchUnmanagedSymlink() throws {
        let fixture = try makeFixture()
        try fixture.writeBundledCLI()
        let otherSource = fixture.scratch.appendingPathComponent("other-kumo").path
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: otherSource))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: otherSource)
        try fixture.makeSymlink(from: otherSource)

        let installer = CLILinkInstaller(
            targetPath: fixture.targetPath,
            bundledCLIPath: fixture.bundledPath
        )

        XCTAssertThrowsError(try installer.uninstall(prompt: "test"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.targetPath))
    }

    // MARK: - Helpers

    private struct Fixture {
        let scratch: URL
        let bundledPath: String
        let missingBundledPath: String
        let targetPath: String

        func writeBundledCLI() throws {
            let url = URL(fileURLWithPath: bundledPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\necho bundled\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledPath)
        }

        func makeSymlink(from source: String) throws {
            if FileManager.default.fileExists(atPath: targetPath) {
                try FileManager.default.removeItem(atPath: targetPath)
            }
            try FileManager.default.createSymbolicLink(
                atPath: targetPath,
                withDestinationPath: source
            )
        }
    }

    private func makeFixture() throws -> Fixture {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: scratch)
        }
        let bin = scratch.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        return Fixture(
            scratch: scratch,
            bundledPath: scratch.appendingPathComponent("Kumo.app/Contents/MacOS/kumo").path,
            missingBundledPath: scratch.appendingPathComponent("Missing/Contents/MacOS/kumo").path,
            targetPath: bin.appendingPathComponent("kumo").path
        )
    }
}

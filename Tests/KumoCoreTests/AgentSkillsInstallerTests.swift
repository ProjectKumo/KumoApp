import XCTest
@testable import KumoCoreKit

final class AgentSkillsInstallerTests: XCTestCase {
    func testValidatesBundledSkillShape() throws {
        let fixture = try makeFixture()
        let installer = try makeInstaller(bundleRoot: fixture.bundleRoot)

        XCTAssertNoThrow(try installer.validateBundledSkills())
        XCTAssertEqual(try installer.loadManifest().skills.map(\.id), ["kumo-cli"])
    }

    func testDryRunReportsUnifiedGlobalTargetsWithoutWritingState() throws {
        let fixture = try makeFixture()
        let installer = try makeInstaller(bundleRoot: fixture.bundleRoot, paths: fixture.paths, home: fixture.home)

        let report = try installer.install(
            scope: .global,
            projectWorkingDirectory: fixture.project,
            dryRun: true,
            force: false
        )

        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(report.copiedSkillIds, ["kumo-cli"])
        XCTAssertEqual(report.destinationRoots.count, AgentSkillsTarget.allCases.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.agentSkillsStateFile.path))
    }

    func testInstallRefusesToOverwriteUntrackedSkill() throws {
        let fixture = try makeFixture()
        let installer = try makeInstaller(bundleRoot: fixture.bundleRoot, paths: fixture.paths, home: fixture.home)
        let existingSkill = fixture.codexBase
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("kumo-cli", isDirectory: true)
        try FileManager.default.createDirectory(at: existingSkill, withIntermediateDirectories: true)
        try Data("custom".utf8).write(to: existingSkill.appendingPathComponent("SKILL.md"))

        XCTAssertThrowsError(
            try installer.install(
                targets: [.codex],
                scope: .global,
                projectWorkingDirectory: fixture.project,
                dryRun: false,
                force: false
            )
        )
    }

    func testStatusIsFilteredPerAgent() throws {
        let fixture = try makeFixture()
        let installer = try makeInstaller(bundleRoot: fixture.bundleRoot, paths: fixture.paths, home: fixture.home)

        _ = try installer.install(
            targets: [.codex],
            scope: .global,
            projectWorkingDirectory: fixture.project,
            dryRun: false,
            force: false
        )

        let codexStatus = try installer.perTargetStatus(
            targets: [.codex],
            scope: .global,
            projectWorkingDirectory: fixture.project
        )
        let cursorStatus = try installer.perTargetStatus(
            targets: [.cursor],
            scope: .global,
            projectWorkingDirectory: fixture.project
        )

        XCTAssertEqual(codexStatus.count, 1)
        XCTAssertTrue(codexStatus[0].installed)
        XCTAssertTrue(codexStatus[0].upToDate)
        XCTAssertEqual(cursorStatus.count, 1)
        XCTAssertFalse(cursorStatus[0].installed)
        XCTAssertFalse(cursorStatus[0].upToDate)
    }

    func testUninstallOnlyRemovesRecordedSkill() throws {
        let fixture = try makeFixture()
        let installer = try makeInstaller(bundleRoot: fixture.bundleRoot, paths: fixture.paths, home: fixture.home)

        _ = try installer.install(
            targets: [.codex],
            scope: .global,
            projectWorkingDirectory: fixture.project,
            dryRun: false,
            force: false
        )
        let installedSkill = fixture.codexBase
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("kumo-cli", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))

        _ = try installer.uninstall(
            targets: [.codex],
            scope: .global,
            projectWorkingDirectory: fixture.project,
            dryRun: false
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: installedSkill.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.agentSkillsStateFile.path))
    }

    private func makeInstaller(
        bundleRoot: URL,
        paths: KumoPaths? = nil,
        home: URL? = nil
    ) throws -> AgentSkillsInstaller {
        try AgentSkillsInstaller(
            bundleRoot: bundleRoot,
            paths: paths ?? KumoPaths(applicationSupportDirectory: temporaryDirectory()),
            homeDirectory: home ?? temporaryDirectory(),
            codexBaseDirectoryOverride: bundleRoot.deletingLastPathComponent().appendingPathComponent("codex", isDirectory: true)
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = temporaryDirectory()
        let bundleRoot = root.appendingPathComponent("KumoAgentSkills", isDirectory: true)
        let skillRoot = bundleRoot.appendingPathComponent("skills/kumo-cli", isDirectory: true)
        try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)

        let manifest = """
        {
          "bundleVersion": "2",
          "skills": [
            {
              "id": "kumo-cli",
              "relativePath": "skills/kumo-cli"
            }
          ]
        }
        """
        try Data(manifest.utf8).write(to: bundleRoot.appendingPathComponent("manifest.json"))

        let skill = """
        ---
        name: kumo-cli
        description: Drive Kumo from coding agents and automation through the `kumo` command-line interface. Use when controlling or troubleshooting Kumo.
        ---

        # Kumo CLI

        ## Quick Start

        Run `kumo doctor --json` first.
        """
        try Data(skill.utf8).write(to: skillRoot.appendingPathComponent("SKILL.md"))

        let paths = KumoPaths(applicationSupportDirectory: root.appendingPathComponent("app-support", isDirectory: true))
        return Fixture(
            bundleRoot: bundleRoot,
            paths: paths,
            home: root.appendingPathComponent("home", isDirectory: true),
            codexBase: root.appendingPathComponent("codex", isDirectory: true),
            project: root.appendingPathComponent("project", isDirectory: true)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private struct Fixture {
    var bundleRoot: URL
    var paths: KumoPaths
    var home: URL
    var codexBase: URL
    var project: URL
}

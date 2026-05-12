import XCTest
@testable import KumoCoreKit

final class SubStoreManagerTests: XCTestCase {
    func testMarkEnabledAssignsBackendPort() throws {
        let manager = SubStoreManager(paths: KumoPaths(applicationSupportDirectory: temporaryDirectory()))

        let enabled = try manager.markEnabled(true)

        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(enabled.backendPort, 38324)
        XCTAssertEqual(enabled.host, "127.0.0.1")
        XCTAssertEqual(manager.backendURL(for: enabled)?.absoluteString, "http://127.0.0.1:38324")
    }

    func testCustomBackendURLIsPreferred() throws {
        let manager = SubStoreManager(paths: KumoPaths(applicationSupportDirectory: temporaryDirectory()))
        let status = SubStoreStatus(
            isEnabled: true,
            usesCustomBackend: true,
            customBackendURL: URL(string: "https://sub.example.com")
        )

        XCTAssertEqual(manager.backendURL(for: status), URL(string: "https://sub.example.com"))
    }

    func testPrepareResourcesCopiesBundledPayloadAndBuildsNodeLaunchPlan() throws {
        let supportDirectory = temporaryDirectory()
        let bundledResources = try makeBundledResourcesFixture()
        let paths = KumoPaths(applicationSupportDirectory: supportDirectory)
        let manager = SubStoreManager(paths: paths, bundledResourceDirectory: bundledResources)

        var status = try manager.prepareResources()
        status.isEnabled = true
        status.backendPort = 38324
        status.usesProxy = true
        try manager.updateStatus(status)

        let plan = try manager.launchPlan(for: status, mixedPort: 7890)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.subStoreNodeExecutable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.subStoreBackendBundle.path))
        XCTAssertEqual(status.installedResourceVersion, "test")
        XCTAssertEqual(plan.backendCommand?.executable, paths.subStoreNodeExecutable.path)
        XCTAssertEqual(plan.backendCommand?.arguments, [paths.subStoreBackendBundle.path])
        XCTAssertEqual(plan.backendCommand?.environment?["SUB_STORE_BACKEND_API_PORT"], "38324")
        XCTAssertEqual(plan.backendCommand?.environment?["HTTP_PROXY"], "http://127.0.0.1:7890")
        XCTAssertEqual(plan.backendURL?.absoluteString, "http://127.0.0.1:38324")
    }

    func testCustomBackendDoesNotLaunchLocalProcess() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let manager = SubStoreManager(paths: paths)
        let status = SubStoreStatus(
            isEnabled: true,
            usesCustomBackend: true,
            customBackendURL: URL(string: "https://sub.example.com")
        )

        let plan = try manager.launchPlan(for: status)

        XCTAssertNil(plan.backendCommand)
        XCTAssertEqual(plan.backendURL?.absoluteString, "https://sub.example.com")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeBundledResourcesFixture() throws -> URL {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node/bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("backend"), withIntermediateDirectories: true)
        try """
        {
          "version": "test",
          "nodeExecutableRelativePath": "node/bin/node",
          "backendBundleRelativePath": "backend/sub-store.bundle.js"
        }
        """.data(using: .utf8)?.write(to: root.appendingPathComponent("manifest.json"))
        try "#!/bin/sh\n".data(using: .utf8)?.write(to: root.appendingPathComponent("node/bin/node"))
        try "console.log('substore')\n".data(using: .utf8)?.write(to: root.appendingPathComponent("backend/sub-store.bundle.js"))
        return root
    }
}

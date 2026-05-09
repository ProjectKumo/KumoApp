import XCTest
@testable import KumoCoreKit

final class OverrideRepositoryTests: XCTestCase {
    func testYAMLOverridesPersistContentAndOrder() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let repository = OverrideRepository(paths: paths)

        let first = try repository.addLocalOverride(name: "First", format: .yaml, content: "mixed-port: 1")
        let second = try repository.addLocalOverride(name: "Second", format: .yaml, content: "allow-lan: true")
        try repository.reorderOverrides(ids: [second.id, first.id])

        let items = try repository.listOverrides()
        let yaml = try repository.activeYAMLs()

        XCTAssertEqual(items.map(\.id), [second.id, first.id])
        XCTAssertEqual(yaml, ["allow-lan: true", "mixed-port: 1"])
    }

    func testDeleteOverrideRemovesMetadata() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let repository = OverrideRepository(paths: paths)
        let item = try repository.addLocalOverride(name: "Delete Me", format: .yaml, content: "rules: []")

        try repository.deleteOverride(id: item.id)

        XCTAssertTrue(try repository.listOverrides().isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

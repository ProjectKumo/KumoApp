import XCTest
@testable import KumoCoreKit

final class AppUpdateInstallerTests: XCTestCase {
    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(
            AppUpdateInstaller.shellQuote("Kumo's DMG"),
            "'Kumo'\\''s DMG'"
        )
    }

    func testShellQuoteWrapsPathsWithSpaces() {
        XCTAssertEqual(
            AppUpdateInstaller.shellQuote("/Applications/Kumo App/Kumo.app"),
            "'/Applications/Kumo App/Kumo.app'"
        )
    }
}

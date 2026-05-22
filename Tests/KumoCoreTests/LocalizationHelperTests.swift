import XCTest
@testable import KumoCoreKit

final class LocalizationHelperTests: XCTestCase {
    func testAvailableLocalizationsIncludesMajorLanguages() {
        let languages = availableLocalizationsFromStringCatalog()
        XCTAssertTrue(languages.contains("en"))
        XCTAssertTrue(languages.contains("zh-Hans"))
        XCTAssertTrue(languages.contains("ja"))
        XCTAssertTrue(languages.contains("de"))
        XCTAssertGreaterThanOrEqual(languages.count, 10)
    }
}

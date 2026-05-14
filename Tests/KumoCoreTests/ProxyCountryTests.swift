import XCTest
@testable import KumoCoreKit

final class ProxyCountryTests: XCTestCase {
    func testEmbeddedFlagEmojiIsReturnedVerbatim() {
        XCTAssertEqual(ProxyCountry.flag(for: "🇭🇰 Hong Kong 01"), "🇭🇰")
        XCTAssertEqual(ProxyCountry.flag(for: "Backup 🇯🇵 Tokyo Premium"), "🇯🇵")
    }

    func testEmbeddedFlagRecoversIsoCode() {
        XCTAssertEqual(ProxyCountry.code(for: "🇭🇰 Hong Kong 01"), "HK")
        XCTAssertEqual(ProxyCountry.code(for: "🇸🇬 Premium"), "SG")
    }

    func testIsoCodeKeywordHit() {
        XCTAssertEqual(ProxyCountry.code(for: "HK-01"), "HK")
        XCTAssertEqual(ProxyCountry.code(for: "us-la-02"), "US")
        XCTAssertEqual(ProxyCountry.flag(for: "JP-Tokyo"), "🇯🇵")
    }

    func testEnglishLongNameKeywordHit() {
        XCTAssertEqual(ProxyCountry.code(for: "United States Premium"), "US")
        XCTAssertEqual(ProxyCountry.code(for: "Singapore Edge"), "SG")
        XCTAssertEqual(ProxyCountry.flag(for: "Hong Kong Backup"), "🇭🇰")
    }

    func testChineseRegionKeywordHit() {
        XCTAssertEqual(ProxyCountry.code(for: "香港 01 IPLC"), "HK")
        XCTAssertEqual(ProxyCountry.code(for: "日本节点-高速"), "JP")
        XCTAssertEqual(ProxyCountry.code(for: "新加坡 Premium"), "SG")
        XCTAssertEqual(ProxyCountry.code(for: "美国洛杉矶 03"), "US")
    }

    func testAsciiBoundaryAvoidsSubstringFalsePositive() {
        // "HK" should not match inside "thunderhook", and "US" should not
        // match inside "username".
        XCTAssertNil(ProxyCountry.code(for: "thunderhook-relay"))
        XCTAssertNil(ProxyCountry.code(for: "username-only"))
    }

    func testReturnsNilWhenNothingMatches() {
        XCTAssertNil(ProxyCountry.code(for: "Custom Relay 01"))
        XCTAssertNil(ProxyCountry.flag(for: "Auto"))
        XCTAssertNil(ProxyCountry.flag(for: "DIRECT"))
    }

    func testFlagForRegionCodeBuildsEmoji() {
        XCTAssertEqual(ProxyCountry.flag(forRegionCode: "us"), "🇺🇸")
        XCTAssertEqual(ProxyCountry.flag(forRegionCode: "HK"), "🇭🇰")
        XCTAssertNil(ProxyCountry.flag(forRegionCode: "USA"))
        XCTAssertNil(ProxyCountry.flag(forRegionCode: "u"))
        XCTAssertNil(ProxyCountry.flag(forRegionCode: "12"))
    }

    func testEmbeddedFlagTakesPriorityOverKeyword() {
        // "🇯🇵" must win even though the name also contains "HK" in tail text.
        XCTAssertEqual(ProxyCountry.flag(for: "🇯🇵 JP Backup-HK"), "🇯🇵")
        XCTAssertEqual(ProxyCountry.code(for: "🇯🇵 JP Backup-HK"), "JP")
    }

    func testDisplayNameRemovesEmbeddedFlagEmoji() {
        XCTAssertEqual(ProxyCountry.displayName(for: "🇭🇰 香港 01"), "香港 01")
        XCTAssertEqual(ProxyCountry.displayName(for: "香港 🇭🇰 01"), "香港 01")
        XCTAssertEqual(ProxyCountry.displayName(for: "🇭🇰-香港 01"), "香港 01")
        XCTAssertEqual(ProxyCountry.displayName(for: "🇭🇰 🇯🇵 Relay"), "Relay")
    }

    func testDisplayNameKeepsNonFlagEmoji() {
        XCTAssertEqual(ProxyCountry.displayName(for: "🚀 节点选择"), "🚀 节点选择")
        XCTAssertEqual(ProxyCountry.displayName(for: "🦥 懒人 01"), "🦥 懒人 01")
    }

    func testDisplayNameDoesNotNormalizeNamesWithoutFlags() {
        XCTAssertEqual(ProxyCountry.displayName(for: "- Custom   Relay"), "- Custom   Relay")
    }

    func testDisplayNameFallsBackWhenFlagWasOnlyText() {
        XCTAssertEqual(ProxyCountry.displayName(for: "🇭🇰"), "🇭🇰")
    }

    func testDataDrivenRegionsAreRecognizedWithoutManualEntries() {
        // These countries are not in `manualAliases` — they should still
        // resolve because the keyword table is derived from Foundation's
        // ICU localized region names.
        XCTAssertEqual(ProxyCountry.code(for: "Brazil Premium"), "BR")
        XCTAssertEqual(ProxyCountry.code(for: "Argentina Edge"), "AR")
        XCTAssertEqual(ProxyCountry.code(for: "Sweden Fast"), "SE")
        XCTAssertEqual(ProxyCountry.code(for: "巴西 01"), "BR")
    }

    func testPhase2PrefersEarliestIsoTokenInName() {
        // `LA` (Laos) is a valid ISO alpha-2 code, but in `us-la-02` the
        // `us` token appears first and should win. Without position-based
        // matching we would get LA back from alphabetical ordering.
        XCTAssertEqual(ProxyCountry.code(for: "us-la-02"), "US")
        XCTAssertEqual(ProxyCountry.code(for: "jp-osaka-01"), "JP")
        // Conversely, when LA really is the only token, it should win.
        XCTAssertEqual(ProxyCountry.code(for: "la-vientiane-01"), "LA")
    }

    func testUkAliasResolvesToGbViaIsoLookup() {
        // `UK` is not an ISO 3166-1 alpha-2 code (GB is), so the alias has to
        // come from `manualAliases` and feed Phase 2 lookup.
        XCTAssertEqual(ProxyCountry.code(for: "UK-01"), "GB")
        XCTAssertEqual(ProxyCountry.flag(for: "UK Edge"), "🇬🇧")
    }
}

import XCTest
@testable import KumoCoreKit

final class ProxyGeoLookupTests: XCTestCase {
    func testFirstLookupHitsFetcherAndCachesResult() async throws {
        let fetcher = StubGeoFetcher(map: ["hk-01.example.com": "HK"])
        let cacheURL = makeTempCacheURL()
        let lookup = ProxyGeoLookup(cacheURL: cacheURL, fetcher: fetcher)

        let first = await lookup.country(for: "hk-01.example.com")
        let second = await lookup.country(for: "hk-01.example.com")
        let calls = await fetcher.callCount

        XCTAssertEqual(first, "HK")
        XCTAssertEqual(second, "HK")
        XCTAssertEqual(calls, 1, "Cached lookup should not refetch")
    }

    func testCachePersistsAcrossInstances() async throws {
        let fetcher = StubGeoFetcher(map: ["us-la.example.com": "US"])
        let cacheURL = makeTempCacheURL()

        do {
            let lookup = ProxyGeoLookup(cacheURL: cacheURL, fetcher: fetcher)
            _ = await lookup.country(for: "us-la.example.com")
        }

        // Fresh instance, same cache file — second fetcher call should not happen.
        let revivedFetcher = StubGeoFetcher(map: [:])
        let revived = ProxyGeoLookup(cacheURL: cacheURL, fetcher: revivedFetcher)
        let cached = await revived.country(for: "us-la.example.com")
        let revivedCalls = await revivedFetcher.callCount

        XCTAssertEqual(cached, "US")
        XCTAssertEqual(revivedCalls, 0)
    }

    func testFailureCooldownPreventsImmediateRefetch() async throws {
        let fetcher = StubGeoFetcher(map: [:], throwsForHosts: ["broken.example.com"])
        let cacheURL = makeTempCacheURL()
        let lookup = ProxyGeoLookup(
            cacheURL: cacheURL,
            fetcher: fetcher,
            failureCooldown: 60,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let first = await lookup.country(for: "broken.example.com")
        let second = await lookup.country(for: "broken.example.com")
        let calls = await fetcher.callCount

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(calls, 1, "Cooldown should suppress repeat fetches")
    }

    func testExpiredCacheIsRefetched() async throws {
        let fetcher = StubGeoFetcher(map: ["tw.example.com": "TW"])
        let cacheURL = makeTempCacheURL()
        let clock = MutableClock(Date(timeIntervalSince1970: 0))
        let lookup = ProxyGeoLookup(
            cacheURL: cacheURL,
            fetcher: fetcher,
            ttl: 100,
            now: { clock.now }
        )

        _ = await lookup.country(for: "tw.example.com")
        let firstCalls = await fetcher.callCount
        XCTAssertEqual(firstCalls, 1)

        clock.now = Date(timeIntervalSince1970: 1_000) // Past TTL.
        _ = await lookup.country(for: "tw.example.com")
        let secondCalls = await fetcher.callCount
        XCTAssertEqual(secondCalls, 2)
    }

    func testBatchCountriesDedupesAndConcurrencyBounded() async throws {
        let fetcher = StubGeoFetcher(map: [
            "a.example.com": "US",
            "b.example.com": "JP",
            "c.example.com": "HK"
        ])
        let cacheURL = makeTempCacheURL()
        let lookup = ProxyGeoLookup(cacheURL: cacheURL, fetcher: fetcher)

        // Three unique hosts but six entries — dedup should yield 3 fetches.
        let result = await lookup.countries(for: [
            "a.example.com", "a.example.com", "b.example.com",
            "b.example.com", "c.example.com", "c.example.com"
        ], concurrency: 2)

        let calls = await fetcher.callCount
        XCTAssertEqual(result["a.example.com"], "US")
        XCTAssertEqual(result["b.example.com"], "JP")
        XCTAssertEqual(result["c.example.com"], "HK")
        XCTAssertEqual(calls, 3)
    }

    func testCachedCountryReadsWithoutNetwork() async throws {
        let fetcher = StubGeoFetcher(map: ["sg.example.com": "SG"])
        let cacheURL = makeTempCacheURL()
        let lookup = ProxyGeoLookup(cacheURL: cacheURL, fetcher: fetcher)

        // No call yet — cache empty.
        let preflight = await lookup.cachedCountry(for: "sg.example.com")
        XCTAssertNil(preflight)

        _ = await lookup.country(for: "sg.example.com")

        let cached = await lookup.cachedCountry(for: "sg.example.com")
        XCTAssertEqual(cached, "SG")
    }

    // MARK: - Helpers

    private func makeTempCacheURL() -> URL {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kumo-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp.appendingPathComponent("proxy-geo-cache.json")
    }
}

/// Mutable wall clock used to advance time in cache-expiry tests. Wrapped
/// in a reference type marked `@unchecked Sendable` so the `now` closure
/// (which itself must be `Sendable`) can read/write the value across
/// concurrency domains in the test process.
private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ initial: Date) { self.now = initial }
}

private actor StubGeoFetcher: ProxyGeoFetching {
    private let map: [String: String]
    private let throwsForHosts: Set<String>
    private(set) var callCount = 0

    init(map: [String: String], throwsForHosts: Set<String> = []) {
        self.map = Dictionary(uniqueKeysWithValues: map.map { ($0.key.lowercased(), $0.value) })
        self.throwsForHosts = Set(throwsForHosts.map { $0.lowercased() })
    }

    func countryCode(for hostOrIP: String) async throws -> String? {
        callCount += 1
        let key = hostOrIP.lowercased()
        if throwsForHosts.contains(key) {
            throw URLError(.cannotConnectToHost)
        }
        return map[key]
    }
}

import Foundation

/// Abstraction over the network call that turns a server hostname / IP into
/// an ISO 3166-1 alpha-2 country code. Injectable so tests can avoid hitting
/// the public network.
public protocol ProxyGeoFetching: Sendable {
    func countryCode(for hostOrIP: String) async throws -> String?
}

/// Default fetcher backed by [ipwho.is](https://ipwho.is/) — a free HTTPS API
/// that accepts both IP addresses and hostnames, returning the inferred
/// country code in the `country_code` field. Failure modes (`success: false`,
/// non-2xx HTTP, parse errors) all surface as `throws` so the caller can
/// decide whether to cache the negative result or retry later.
public struct DefaultProxyGeoFetcher: ProxyGeoFetching {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://ipwho.is")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func countryCode(for hostOrIP: String) async throws -> String? {
        let escaped = hostOrIP.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? hostOrIP
        guard let url = URL(string: "\(baseURL.absoluteString)/\(escaped)?fields=success,country_code") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        struct Payload: Decodable {
            let success: Bool?
            // ipwho.is returns "country_code" (snake_case) — keep coding key
            // explicit so the type works with default JSONDecoder strategy.
            let countryCode: String?

            enum CodingKeys: String, CodingKey {
                case success
                case countryCode = "country_code"
            }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if payload.success == false {
            return nil
        }
        let code = payload.countryCode?.uppercased() ?? ""
        return code.count == 2 ? code : nil
    }
}

/// Persistent, deduplicated GeoIP lookup with TTL and failure cooldown.
///
/// Behaviour:
///
/// - First request for a host hits the network, caches the result, and
///   returns. Subsequent requests within the TTL hit the in-memory / on-disk
///   cache.
/// - Concurrent requests for the same host coalesce into a single in-flight
///   task so we don't fan out N identical HTTP calls.
/// - Failures (network error, non-2xx, `success: false`) start a short
///   cooldown during which the host returns `nil` without touching the
///   network. This protects against a single bad host taking down a batch.
/// - Cache lives at `paths.proxyGeoCacheFile` and survives restarts.
public actor ProxyGeoLookup {
    public struct CacheEntry: Codable, Equatable, Sendable {
        public let country: String
        public let fetchedAt: Date

        public init(country: String, fetchedAt: Date) {
            self.country = country
            self.fetchedAt = fetchedAt
        }
    }

    public static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60
    public static let defaultFailureCooldown: TimeInterval = 5 * 60
    public static let defaultConcurrency: Int = 5

    private let cacheURL: URL
    private let fetcher: ProxyGeoFetching
    private let ttl: TimeInterval
    private let failureCooldown: TimeInterval
    private let now: @Sendable () -> Date

    private var cache: [String: CacheEntry] = [:]
    private var failures: [String: Date] = [:]
    private var inflight: [String: Task<String?, Never>] = [:]

    public init(
        cacheURL: URL,
        fetcher: ProxyGeoFetching = DefaultProxyGeoFetcher(),
        ttl: TimeInterval = ProxyGeoLookup.defaultTTL,
        failureCooldown: TimeInterval = ProxyGeoLookup.defaultFailureCooldown,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cacheURL = cacheURL
        self.fetcher = fetcher
        self.ttl = ttl
        self.failureCooldown = failureCooldown
        self.now = now
        // Inline the disk load: Swift 6 actor init cannot call isolated
        // instance methods. We need it eager so `cachedCountry(for:)` works
        // immediately after construction without an awaited warm-up.
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder.iso8601.decode([String: CacheEntry].self, from: data) {
            let cutoff = now().addingTimeInterval(-ttl)
            self.cache = decoded.filter { $0.value.fetchedAt > cutoff }
        }
    }

    /// Returns the cached country code for `hostOrIP` if one is available
    /// without touching the network. Used to render an initial flag before
    /// any async lookup completes.
    public func cachedCountry(for hostOrIP: String) -> String? {
        let key = normalize(hostOrIP)
        guard !key.isEmpty, let entry = cache[key] else { return nil }
        guard now().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry.country
    }

    /// Looks up the country code for a single host, honoring cache, failure
    /// cooldown, and in-flight deduplication.
    public func country(for hostOrIP: String) async -> String? {
        let key = normalize(hostOrIP)
        guard !key.isEmpty else { return nil }

        let currentTime = now()
        if let entry = cache[key], currentTime.timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.country
        }
        if let failedAt = failures[key], currentTime.timeIntervalSince(failedAt) < failureCooldown {
            return nil
        }
        if let task = inflight[key] {
            return await task.value
        }

        let task = Task { [self] in
            await self.fetchAndStore(key: key)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    /// Resolves country codes for the given hosts with bounded concurrency.
    /// Returns a `host → country` map containing only successful lookups.
    public func countries(
        for hosts: [String],
        concurrency: Int = ProxyGeoLookup.defaultConcurrency
    ) async -> [String: String] {
        let unique = Array(Set(hosts.map(normalize))).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [:] }
        let limit = max(1, concurrency)

        return await withTaskGroup(of: (String, String?).self) { group in
            var iterator = unique.makeIterator()
            var inflightCount = 0

            func spawnNext() -> Bool {
                guard let host = iterator.next() else { return false }
                group.addTask { [weak self] in
                    let value = await self?.country(for: host) ?? nil
                    return (host, value)
                }
                inflightCount += 1
                return true
            }

            for _ in 0..<limit {
                guard spawnNext() else { break }
            }

            var results: [String: String] = [:]
            while inflightCount > 0 {
                guard let next = await group.next() else { break }
                inflightCount -= 1
                if let code = next.1 {
                    results[next.0] = code
                }
                _ = spawnNext()
            }
            return results
        }
    }

    /// Drops the in-memory and on-disk cache. Mostly useful for tests and
    /// for a future "Clear cached country flags" debug action.
    public func clearCache() {
        cache.removeAll()
        failures.removeAll()
        saveToDisk()
    }

    // MARK: - Private

    private func fetchAndStore(key: String) async -> String? {
        do {
            let code = try await fetcher.countryCode(for: key)
            if let code, code.count == 2 {
                cache[key] = CacheEntry(country: code.uppercased(), fetchedAt: now())
                failures[key] = nil
                saveToDisk()
                return code.uppercased()
            }
            failures[key] = now()
            return nil
        } catch {
            failures[key] = now()
            return nil
        }
    }

    private func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func saveToDisk() {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.iso8601.encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

import Foundation

public struct ControllerVersion: Codable, Equatable, Sendable {
    public var version: String?
    public var meta: Bool?
}

public struct MihomoControllerClient: Sendable {
    private static let defaultDelayTestURL = "https://www.gstatic.com/generate_204"

    public var endpoint: ControllerEndpoint
    public var session: URLSession

    public init(endpoint: ControllerEndpoint = ControllerEndpoint(), session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func version() async throws -> ControllerVersion {
        try await send("/version", method: "GET", response: ControllerVersion.self)
    }

    public func currentMode() async throws -> OutboundMode {
        let object = try await sendJSON("/configs", method: "GET")
        guard let modeValue = object["mode"] as? String,
              let mode = OutboundMode(rawValue: modeValue) else {
            return .rule
        }
        return mode
    }

    public func setMode(_ mode: OutboundMode) async throws {
        _ = try await sendJSON("/configs", method: "PATCH", body: ["mode": mode.rawValue])
    }

    public func patchConfiguration(_ patch: [String: Any]) async throws {
        _ = try await sendJSON("/configs", method: "PATCH", body: patch)
    }

    public func configuration() async throws -> CoreConfigurationSnapshot {
        let object = try await sendJSON("/configs", method: "GET")
        let version = try? await version()
        let mode = (object["mode"] as? String).flatMap(OutboundMode.init(rawValue:)) ?? .rule
        let mixedPort = intValue(object["mixed-port"]) ?? intValue(object["mixedPort"]) ?? 7890
        let logLevel = object["log-level"] as? String ?? "info"
        let allowLAN = object["allow-lan"] as? Bool ?? false
        let ipv6 = object["ipv6"] as? Bool ?? false
        let tun = object["tun"] as? [String: Any]
        let dns = object["dns"] as? [String: Any]
        let sniffer = object["sniffer"] as? [String: Any]
        let topLevelHosts = policyValueDict(from: object["hosts"])
        var parsedDNS = dnsSettings(from: dns)
        if parsedDNS == nil, !topLevelHosts.isEmpty {
            parsedDNS = DnsSettings(isEnabled: false)
        }
        parsedDNS?.hosts = topLevelHosts

        return CoreConfigurationSnapshot(
            version: version?.version,
            mode: mode,
            mixedPort: mixedPort,
            logLevel: logLevel,
            allowLAN: allowLAN,
            ipv6: ipv6,
            geoData: geoData(from: object),
            tunEnabled: tun?["enable"] as? Bool ?? false,
            dnsEnabled: parsedDNS?.isEnabled ?? false,
            snifferEnabled: sniffer?["enable"] as? Bool ?? false,
            dns: parsedDNS,
            sniffer: snifferSettings(from: sniffer)
        )
    }

    public func proxyGroups() async throws -> [ProxyGroup] {
        let root = try await sendJSON("/proxies", method: "GET")
        guard let proxies = root["proxies"] as? [String: [String: Any]] else {
            return []
        }

        return proxies
            .compactMap { name, value -> ProxyGroup? in
                guard let allNames = value["all"] as? [String],
                      value["hidden"] as? Bool != true else {
                    return nil
                }

                let nodes = allNames.map { nodeName -> ProxyNode in
                    let proxy = proxies[nodeName]
                    let delay = (proxies[nodeName]?["history"] as? [[String: Any]])?.last?["delay"] as? Int
                    return ProxyNode(name: nodeName, type: proxy?["type"] as? String, delay: delay)
                }

                return ProxyGroup(
                    name: name,
                    selectedProxyName: value["now"] as? String,
                    proxies: nodes,
                    testURL: value["testUrl"] as? String
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func selectProxy(group: String, name: String) async throws {
        let encodedGroup = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
        _ = try await sendJSON("/proxies/\(encodedGroup)", method: "PUT", body: ["name": name])
    }

    public func proxyDelay(proxy: String, testURL: String? = nil) async throws -> Int? {
        let encodedProxy = proxy.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proxy
        let delayURL = testURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestURL: String
        if let delayURL, !delayURL.isEmpty {
            requestURL = delayURL
        } else {
            requestURL = Self.defaultDelayTestURL
        }
        let query = [
            "url": requestURL,
            "timeout": "5000"
        ]
        let object = try await sendJSON("/proxies/\(encodedProxy)/delay", method: "GET", query: query)
        return intValue(object["delay"])
    }

    public func groupDelay(group: ProxyGroup) async throws -> [ProxyNode] {
        var nodes: [ProxyNode] = []
        for proxy in group.proxies {
            let delay = try? await proxyDelay(proxy: proxy.name, testURL: group.testURL)
            nodes.append(ProxyNode(name: proxy.name, type: proxy.type, delay: delay ?? proxy.delay))
        }
        return nodes
    }

    public func rules() async throws -> [RuleEntry] {
        let root = try await sendJSON("/rules", method: "GET")
        let rules = root["rules"] as? [[String: Any]] ?? []
        return rules.enumerated().map { index, rule in
            let extra = rule["extra"] as? [String: Any] ?? [:]
            return RuleEntry(
                id: "\(index)-\(rule["type"] as? String ?? "")-\(rule["payload"] as? String ?? "")",
                index: index,
                type: rule["type"] as? String ?? "-",
                payload: rule["payload"] as? String ?? "-",
                proxy: rule["proxy"] as? String ?? "-",
                isEnabled: !(extra["disabled"] as? Bool ?? false),
                hitCount: intValue(extra["hitCount"]) ?? 0,
                missCount: intValue(extra["missCount"]) ?? 0,
                lastHit: extra["hitAt"] as? String,
                lastMiss: extra["missAt"] as? String,
                size: intValue(rule["size"]) ?? intValue(extra["size"]) ?? 0
            )
        }
    }

    public func setRulesDisabled(_ disabledByIndex: [Int: Bool]) async throws {
        let body = Dictionary(uniqueKeysWithValues: disabledByIndex.map { (String($0.key), $0.value) })
        _ = try await sendJSON("/rules/disable", method: "PATCH", body: body)
    }

    public func proxyProviders() async throws -> [ProxyProviderEntry] {
        let root = try await sendJSON("/providers/proxies", method: "GET")
        let providers = root["providers"] as? [String: [String: Any]] ?? [:]
        return providers.values.compactMap(proxyProvider(from:))
            .filter { $0.vehicleType != "Compatible" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func updateProxyProvider(name: String) async throws {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        _ = try await sendJSON("/providers/proxies/\(encodedName)", method: "PUT")
    }

    public func ruleProviders() async throws -> [RuleProviderEntry] {
        let root = try await sendJSON("/providers/rules", method: "GET")
        let providers = root["providers"] as? [String: [String: Any]] ?? [:]
        return providers.values.compactMap(ruleProvider(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func updateRuleProvider(name: String) async throws {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        _ = try await sendJSON("/providers/rules/\(encodedName)", method: "PUT")
    }

    public func upgradeGeoData() async throws {
        _ = try await sendJSON("/upgrade/geo", method: "POST")
    }

    public func logStream(level: String = "info") -> AsyncThrowingStream<LogEntry, Error> {
        // Logs are append-only; callers expect a fresh stream of entries on every (re)connect.
        streamWebSocket(
            request: webSocketRequest(path: "/logs", query: ["level": level]),
            parser: { self.logEntry(from: $0) },
            idleValue: nil
        )
    }

    public func trafficStream() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        // Yield a zero snapshot whenever the websocket disconnects so the UI doesn't keep displaying
        // stale speeds; mihomo will resume emitting real values once the new connection is up.
        streamWebSocket(
            request: webSocketRequest(path: "/traffic"),
            parser: { self.trafficSnapshot(from: $0) },
            idleValue: TrafficSnapshot()
        )
    }

    public func memoryStream() -> AsyncThrowingStream<MemorySnapshot, Error> {
        streamWebSocket(
            request: webSocketRequest(path: "/memory"),
            parser: { self.memorySnapshot(from: $0) },
            idleValue: MemorySnapshot()
        )
    }

    public func connections() async throws -> [ConnectionEntry] {
        let root = try await sendJSON("/connections", method: "GET")
        let connections = root["connections"] as? [[String: Any]] ?? []
        return connections.compactMap { connection in
            guard let id = connection["id"] as? String else {
                return nil
            }
            let metadata = connection["metadata"] as? [String: Any] ?? [:]
            let host = metadata["host"] as? String
                ?? metadata["sniffHost"] as? String
                ?? metadata["destinationIP"] as? String
                ?? metadata["remoteDestination"] as? String
                ?? "-"
            let isInnerConnection = metadata["type"] as? String == "Inner"
            let process = metadata["process"] as? String
                ?? (isInnerConnection ? "mihomo" : nil)
            let processPath = metadata["processPath"] as? String
                ?? (isInnerConnection ? "mihomo" : nil)

            return ConnectionEntry(
                id: id,
                host: host,
                process: process,
                processPath: processPath,
                rule: connection["rule"] as? String,
                chain: connection["chains"] as? [String] ?? [],
                upload: intValue(connection["upload"]) ?? 0,
                download: intValue(connection["download"]) ?? 0,
                uploadSpeed: intValue(connection["uploadSpeed"]) ?? 0,
                downloadSpeed: intValue(connection["downloadSpeed"]) ?? 0,
                startedAt: connection["start"] as? String
            )
        }
    }

    public func closeConnection(id: String) async throws {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await sendJSON("/connections/\(encodedID)", method: "DELETE")
    }

    public func closeConnections(matchingProxy proxy: String? = nil) async throws {
        if let proxy, !proxy.isEmpty {
            let currentConnections = try await connections()
            for connection in currentConnections where connection.chain.contains(proxy) {
                try? await closeConnection(id: connection.id)
            }
            return
        }

        _ = try await sendJSON("/connections", method: "DELETE")
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String,
        response: Response.Type
    ) async throws -> Response {
        let data = try await sendData(path, method: method, body: nil)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sendJSON(
        _ path: String,
        method: String,
        body: [String: Any]? = nil,
        query: [String: String] = [:]
    ) async throws -> [String: Any] {
        let data = try await sendData(path, method: method, body: body, query: query)
        if data.isEmpty {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func sendData(
        _ path: String,
        method: String,
        body: [String: Any]?,
        query: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 15
        if !endpoint.secret.isEmpty {
            request.setValue("Bearer \(endpoint.secret)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw KumoError.controllerResponse(httpResponse.statusCode, String(decoding: data, as: UTF8.self))
        }

        return data
    }

    private func url(path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func webSocketURL(path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func webSocketRequest(path: String, query: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: webSocketURL(path: path, query: query))
        // Mihomo's external-controller authenticates websocket upgrades the same way it does HTTP
        // requests when a `secret` is configured; without this header the WS would 401 silently.
        if !endpoint.secret.isEmpty {
            request.setValue("Bearer \(endpoint.secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Long-lived websocket subscription that auto-reconnects on disconnection.
    ///
    /// The stream finishes only when the consumer cancels (via `continuation.onTermination` or
    /// task cancellation). Transient connection failures are swallowed and retried after a short
    /// delay so a brief mihomo restart or network hiccup doesn't permanently freeze the UI.
    /// When the connection drops after at least one message has been observed, an `idleValue`
    /// (if provided) is yielded so consumers can reset speed/memory gauges to zero.
    private func streamWebSocket<Value: Sendable>(
        request: URLRequest,
        parser: @escaping @Sendable (String) -> Value?,
        idleValue: Value?,
        reconnectDelayNanoseconds: UInt64 = 1_000_000_000
    ) -> AsyncThrowingStream<Value, Error> {
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                var sawAnyMessage = false
                while !Task.isCancelled {
                    let socket = session.webSocketTask(with: request)
                    socket.resume()

                    let receivedDuringConnection = await Self.consumeWebSocket(
                        socket,
                        parser: parser,
                        yield: { continuation.yield($0) }
                    )

                    socket.cancel(with: .goingAway, reason: nil)
                    if Task.isCancelled { break }

                    // Reset gauges when an established stream drops; skip on first-attempt failures
                    // to avoid flickering between unknown and zero before any data has been seen.
                    if (receivedDuringConnection || sawAnyMessage), let idleValue {
                        continuation.yield(idleValue)
                    }
                    sawAnyMessage = sawAnyMessage || receivedDuringConnection

                    do {
                        try await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func consumeWebSocket<Value>(
        _ task: URLSessionWebSocketTask,
        parser: (String) -> Value?,
        yield: (Value) -> Void
    ) async -> Bool {
        var receivedAtLeastOne = false
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let text: String?
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }
                if let text, let parsed = parser(text) {
                    yield(parsed)
                    receivedAtLeastOne = true
                }
            } catch {
                return receivedAtLeastOne
            }
        }
        return receivedAtLeastOne
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func geoData(from object: [String: Any]) -> GeoDataSettings {
        let geoxURL = object["geox-url"] as? [String: Any] ?? [:]
        return GeoDataSettings(
            geoIPURL: stringValue(geoxURL["geoip"] ?? geoxURL["geo-ip"]) ?? GeoDataSettings().geoIPURL,
            geoSiteURL: stringValue(geoxURL["geosite"] ?? geoxURL["geo-site"]) ?? GeoDataSettings().geoSiteURL,
            mmdbURL: stringValue(geoxURL["mmdb"]) ?? GeoDataSettings().mmdbURL,
            asnURL: stringValue(geoxURL["asn"]) ?? GeoDataSettings().asnURL,
            autoUpdate: object["geo-auto-update"] as? Bool ?? false,
            updateIntervalHours: intValue(object["geo-update-interval"]) ?? 24,
            usesDatMode: object["geodata-mode"] as? Bool ?? false
        )
    }

    private func proxyProvider(from object: [String: Any]) -> ProxyProviderEntry? {
        guard let name = object["name"] as? String else { return nil }
        let subscription = object["subscriptionInfo"] as? [String: Any]
        return ProxyProviderEntry(
            name: name,
            vehicleType: object["vehicleType"] as? String ?? "-",
            updatedAt: object["updatedAt"] as? String,
            proxyCount: (object["proxies"] as? [Any])?.count ?? 0,
            subscriptionInfo: subscription.map(providerSubscriptionInfo(from:))
        )
    }

    private func ruleProvider(from object: [String: Any]) -> RuleProviderEntry? {
        guard let name = object["name"] as? String else { return nil }
        return RuleProviderEntry(
            name: name,
            vehicleType: object["vehicleType"] as? String ?? "-",
            behavior: object["behavior"] as? String ?? "-",
            format: object["format"] as? String ?? "-",
            updatedAt: object["updatedAt"] as? String,
            ruleCount: intValue(object["ruleCount"]) ?? 0
        )
    }

    private func providerSubscriptionInfo(from object: [String: Any]) -> ProviderSubscriptionInfo {
        ProviderSubscriptionInfo(
            upload: intValue(object["Upload"] ?? object["upload"]) ?? 0,
            download: intValue(object["Download"] ?? object["download"]) ?? 0,
            total: intValue(object["Total"] ?? object["total"]) ?? 0,
            expire: intValue(object["Expire"] ?? object["expire"])
        )
    }

    private func dnsSettings(from object: [String: Any]?) -> DnsSettings? {
        guard let object else { return nil }
        return DnsSettings(
            isEnabled: object["enable"] as? Bool ?? true,
            listen: object["listen"] as? String ?? "",
            ipv6: object["ipv6"] as? Bool ?? false,
            ipv6Timeout: intValue(object["ipv6-timeout"]) ?? 100,
            preferH3: object["prefer-h3"] as? Bool ?? false,
            enhancedMode: object["enhanced-mode"] as? String ?? "fake-ip",
            fakeIPRange: object["fake-ip-range"] as? String ?? "198.18.0.1/16",
            fakeIPRange6: object["fake-ip-range6"] as? String ?? "",
            fakeIPFilter: object["fake-ip-filter"] as? [String] ?? [],
            fakeIPFilterMode: object["fake-ip-filter-mode"] as? String ?? "",
            useHosts: object["use-hosts"] as? Bool ?? false,
            useSystemHosts: object["use-system-hosts"] as? Bool ?? false,
            respectRules: object["respect-rules"] as? Bool ?? false,
            defaultNameserver: object["default-nameserver"] as? [String] ?? [],
            nameserver: object["nameserver"] as? [String] ?? [],
            fallback: object["fallback"] as? [String] ?? [],
            fallbackFilter: fallbackFilterDict(from: object["fallback-filter"]),
            proxyServerNameserver: object["proxy-server-nameserver"] as? [String] ?? [],
            directNameserver: object["direct-nameserver"] as? [String] ?? [],
            directNameserverFollowPolicy: object["direct-nameserver-follow-policy"] as? Bool ?? false,
            nameserverPolicy: policyValueDict(from: object["nameserver-policy"]),
            proxyServerNameserverPolicy: policyValueDict(from: object["proxy-server-nameserver-policy"]),
            cacheAlgorithm: object["cache-algorithm"] as? String ?? "",
            hosts: [:]
        )
    }

    private func snifferSettings(from object: [String: Any]?) -> SnifferSettings? {
        guard let object else { return nil }
        let sniff = object["sniff"] as? [String: [String: Any]]
        return SnifferSettings(
            isEnabled: object["enable"] as? Bool ?? true,
            parsePureIP: object["parse-pure-ip"] as? Bool ?? true,
            forceDNSMapping: object["force-dns-mapping"] as? Bool ?? true,
            overrideDestination: object["override-destination"] as? Bool ?? false,
            httpOverrideDestination: sniff?["HTTP"]?["override-destination"] as? Bool ?? false,
            httpPorts: portList(from: sniff?["HTTP"]?["ports"]),
            tlsPorts: portList(from: sniff?["TLS"]?["ports"]),
            quicPorts: portList(from: sniff?["QUIC"]?["ports"]),
            skipDomain: object["skip-domain"] as? [String] ?? [],
            forceDomain: object["force-domain"] as? [String] ?? [],
            skipDstAddress: object["skip-dst-address"] as? [String] ?? [],
            skipSrcAddress: object["skip-src-address"] as? [String] ?? []
        )
    }

    private func stringDict(from value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }

    private func policyValueDict(from value: Any?) -> [String: PolicyValue] {
        guard let dict = value as? [String: Any] else { return [:] }
        return dict.compactMapValues { anyValue -> PolicyValue? in
            if let str = anyValue as? String {
                return .single(str)
            }
            if let arr = anyValue as? [String] {
                return .multiple(arr)
            }
            return nil
        }
    }

    private func fallbackFilterDict(from value: Any?) -> [String: FallbackFilterValue] {
        guard let dict = value as? [String: Any] else { return [:] }
        return dict.compactMapValues { anyValue -> FallbackFilterValue? in
            if let b = anyValue as? Bool {
                return .bool(b)
            }
            if let str = anyValue as? String {
                return .single(str)
            }
            if let arr = anyValue as? [String] {
                return .multiple(arr)
            }
            return nil
        }
    }

    private func portList(from value: Any?) -> [Int] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { intValue($0) }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        return nil
    }

    // Exposed at internal visibility so unit tests can validate WS payload parsing without
    // standing up a full mock websocket session.
    func trafficSnapshot(from text: String) -> TrafficSnapshot? {
        guard let object = jsonObject(from: text) else {
            return nil
        }
        // Mihomo emits `{up, down, upTotal, downTotal}` where `up`/`down` are bytes-per-second
        // speeds and `upTotal`/`downTotal` are cumulative byte counters. Older or non-meta cores
        // may emit only the `{up, down}` pair, in which case we fall back so totals stay zero.
        let uploadSpeed = intValue(object["up"]) ?? intValue(object["upSpeed"]) ?? intValue(object["uploadSpeed"]) ?? 0
        let downloadSpeed = intValue(object["down"]) ?? intValue(object["downSpeed"]) ?? intValue(object["downloadSpeed"]) ?? 0
        let uploadTotal = intValue(object["upTotal"]) ?? intValue(object["upload"]) ?? 0
        let downloadTotal = intValue(object["downTotal"]) ?? intValue(object["download"]) ?? 0
        return TrafficSnapshot(
            upload: uploadTotal,
            download: downloadTotal,
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed
        )
    }

    private func memorySnapshot(from text: String) -> MemorySnapshot? {
        guard let object = jsonObject(from: text) else {
            return nil
        }
        return MemorySnapshot(
            inUse: intValue(object["inuse"]) ?? intValue(object["inUse"]) ?? 0,
            osLimit: intValue(object["oslimit"]) ?? intValue(object["osLimit"]) ?? 0
        )
    }

    private func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func logEntry(from text: String) -> LogEntry? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LogEntry(id: UUID().uuidString, level: "info", message: text)
        }
        let level = object["type"] as? String ?? object["level"] as? String ?? "info"
        let message = object["payload"] as? String ?? object["message"] as? String ?? text
        return LogEntry(
            id: object["id"] as? String ?? UUID().uuidString,
            level: level,
            message: message,
            time: object["time"] as? String
        )
    }
}

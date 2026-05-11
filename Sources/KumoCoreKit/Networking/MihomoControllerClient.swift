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

        return CoreConfigurationSnapshot(
            version: version?.version,
            mode: mode,
            mixedPort: mixedPort,
            logLevel: logLevel,
            allowLAN: allowLAN,
            ipv6: ipv6,
            geoData: geoData(from: object),
            tunEnabled: tun?["enable"] as? Bool ?? false,
            dnsEnabled: dns?["enable"] as? Bool ?? false,
            snifferEnabled: sniffer?["enable"] as? Bool ?? false
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
        AsyncThrowingStream { continuation in
            let task = session.webSocketTask(with: webSocketURL(path: "/logs", query: ["level": level]))
            task.resume()
            Task {
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text):
                            if let entry = logEntry(from: text) {
                                continuation.yield(entry)
                            }
                        case .data(let data):
                            if let text = String(data: data, encoding: .utf8),
                               let entry = logEntry(from: text) {
                                continuation.yield(entry)
                            }
                        @unknown default:
                            continue
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    public func trafficStream() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = session.webSocketTask(with: webSocketURL(path: "/traffic", query: [:]))
            task.resume()
            Task {
                do {
                    while !Task.isCancelled {
                        if let snapshot = try await receiveSnapshot(from: task, parser: trafficSnapshot(from:)) {
                            continuation.yield(snapshot)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    public func memoryStream() -> AsyncThrowingStream<MemorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = session.webSocketTask(with: webSocketURL(path: "/memory", query: [:]))
            task.resume()
            Task {
                do {
                    while !Task.isCancelled {
                        if let snapshot = try await receiveSnapshot(from: task, parser: memorySnapshot(from:)) {
                            continuation.yield(snapshot)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
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
                ?? metadata["destinationIP"] as? String
                ?? metadata["remoteDestination"] as? String
                ?? "-"

            return ConnectionEntry(
                id: id,
                host: host,
                process: metadata["process"] as? String,
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

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        return nil
    }

    private func receiveSnapshot<Snapshot>(
        from task: URLSessionWebSocketTask,
        parser: (String) -> Snapshot?
    ) async throws -> Snapshot? {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return parser(text)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parser(text)
        @unknown default:
            return nil
        }
    }

    private func trafficSnapshot(from text: String) -> TrafficSnapshot? {
        guard let object = jsonObject(from: text) else {
            return nil
        }
        let upload = intValue(object["up"]) ?? intValue(object["upload"]) ?? 0
        let download = intValue(object["down"]) ?? intValue(object["download"]) ?? 0
        return TrafficSnapshot(
            upload: upload,
            download: download,
            uploadSpeed: intValue(object["uploadSpeed"]) ?? intValue(object["upSpeed"]) ?? upload,
            downloadSpeed: intValue(object["downloadSpeed"]) ?? intValue(object["downSpeed"]) ?? download
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

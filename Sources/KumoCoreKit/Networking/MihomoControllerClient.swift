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

    public func configuration() async throws -> CoreConfigurationSnapshot {
        let object = try await sendJSON("/configs", method: "GET")
        let version = try? await version()
        let mode = (object["mode"] as? String).flatMap(OutboundMode.init(rawValue:)) ?? .rule
        let mixedPort = intValue(object["mixed-port"]) ?? intValue(object["mixedPort"]) ?? 7890
        let logLevel = object["log-level"] as? String ?? "info"
        let allowLAN = object["allow-lan"] as? Bool ?? false
        let tun = object["tun"] as? [String: Any]
        let dns = object["dns"] as? [String: Any]
        let sniffer = object["sniffer"] as? [String: Any]

        return CoreConfigurationSnapshot(
            version: version?.version,
            mode: mode,
            mixedPort: mixedPort,
            logLevel: logLevel,
            allowLAN: allowLAN,
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
                    let delay = (proxies[nodeName]?["history"] as? [[String: Any]])?.last?["delay"] as? Int
                    return ProxyNode(name: nodeName, delay: delay)
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
            nodes.append(ProxyNode(name: proxy.name, delay: delay ?? proxy.delay))
        }
        return nodes
    }

    public func rules() async throws -> [RuleEntry] {
        let root = try await sendJSON("/rules", method: "GET")
        let rules = root["rules"] as? [[String: Any]] ?? []
        return rules.enumerated().map { index, rule in
            RuleEntry(
                id: "\(index)-\(rule["type"] as? String ?? "")-\(rule["payload"] as? String ?? "")",
                type: rule["type"] as? String ?? "-",
                payload: rule["payload"] as? String ?? "-",
                proxy: rule["proxy"] as? String ?? "-"
            )
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
        body: [String: String]? = nil,
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
        body: [String: String]?,
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
}

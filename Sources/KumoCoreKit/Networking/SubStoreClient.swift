import Foundation

public struct SubStoreClient: Sendable {
    public var baseURL: URL
    public var session: URLSession
    public var timeout: TimeInterval

    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    // MARK: - Subscriptions

    public func subscriptions() async throws -> [SubStoreSubscription] {
        try await get("/api/subs", as: SubStoreSubscriptionsResponse.self).data
    }

    public func subscription(name: String) async throws -> SubStoreSubscription {
        try await get(subPath(name), as: SubStoreEnvelope<SubStoreSubscription>.self).data
    }

    public func createSubscription(_ subscription: SubStoreSubscription) async throws -> SubStoreSubscription {
        try await send("/api/subs", method: "POST", body: subscription, as: SubStoreEnvelope<SubStoreSubscription>.self).data
    }

    public func updateSubscription(name: String, _ subscription: SubStoreSubscription) async throws -> SubStoreSubscription {
        try await send(subPath(name), method: "PATCH", body: subscription, as: SubStoreEnvelope<SubStoreSubscription>.self).data
    }

    public func deleteSubscription(name: String, archive: Bool = false) async throws {
        let path = subPath(name)
        let query = archive ? "mode=archive" : nil
        try await send(path, method: "DELETE", query: query)
    }

    public func replaceSubscriptions(_ subscriptions: [SubStoreSubscription]) async throws {
        try await send("/api/subs", method: "PUT", body: subscriptions)
    }

    public func subscriptionFlow(name: String) async throws -> SubStoreFlow {
        try await get("/api/sub/flow/\(percentEncoded(name))", as: SubStoreEnvelope<SubStoreFlow>.self).data
    }

    // MARK: - Collections

    public func collections() async throws -> [SubStoreCollection] {
        try await get("/api/collections", as: SubStoreCollectionsResponse.self).data
    }

    public func collection(name: String) async throws -> SubStoreCollection {
        try await get(collectionPath(name), as: SubStoreEnvelope<SubStoreCollection>.self).data
    }

    public func createCollection(_ collection: SubStoreCollection) async throws -> SubStoreCollection {
        try await send("/api/collections", method: "POST", body: collection, as: SubStoreEnvelope<SubStoreCollection>.self).data
    }

    public func updateCollection(name: String, _ collection: SubStoreCollection) async throws -> SubStoreCollection {
        try await send(collectionPath(name), method: "PATCH", body: collection, as: SubStoreEnvelope<SubStoreCollection>.self).data
    }

    public func deleteCollection(name: String, archive: Bool = false) async throws {
        let query = archive ? "mode=archive" : nil
        try await send(collectionPath(name), method: "DELETE", query: query)
    }

    public func replaceCollections(_ collections: [SubStoreCollection]) async throws {
        try await send("/api/collections", method: "PUT", body: collections)
    }

    // MARK: - Preview

    public func previewSubscription(_ subscription: SubStoreSubscription, target: String = "JSON") async throws -> SubStorePreviewResult {
        try await send(
            "/api/preview/sub",
            method: "POST",
            query: "target=\(target)",
            body: subscription,
            as: SubStorePreviewResponse.self
        ).data
    }

    public func previewCollection(_ collection: SubStoreCollection, target: String = "JSON") async throws -> SubStorePreviewResult {
        try await send(
            "/api/preview/collection",
            method: "POST",
            query: "target=\(target)",
            body: collection,
            as: SubStorePreviewResponse.self
        ).data
    }

    public func previewFile(_ file: SubStoreFile) async throws -> SubStorePreviewResult {
        try await send(
            "/api/preview/file",
            method: "POST",
            body: file,
            as: SubStorePreviewResponse.self
        ).data
    }

    // MARK: - Files

    public func files() async throws -> [SubStoreFile] {
        try await get("/api/files", as: SubStoreFilesResponse.self).data
    }

    public func createFile(_ file: SubStoreFile) async throws -> SubStoreFile {
        try await send("/api/files", method: "POST", body: file, as: SubStoreEnvelope<SubStoreFile>.self).data
    }

    public func updateFile(name: String, _ file: SubStoreFile) async throws -> SubStoreFile {
        try await send("/api/file/\(percentEncoded(name))", method: "PATCH", body: file, as: SubStoreEnvelope<SubStoreFile>.self).data
    }

    public func deleteFile(name: String) async throws {
        try await send("/api/file/\(percentEncoded(name))", method: "DELETE")
    }

    // MARK: - Modules

    public func modules() async throws -> [SubStoreModule] {
        try await get("/api/modules", as: SubStoreModulesResponse.self).data
    }

    public func module(name: String) async throws -> SubStoreModule {
        try await get("/api/module/\(percentEncoded(name))", as: SubStoreEnvelope<SubStoreModule>.self).data
    }

    public func updateModule(name: String, content: String) async throws {
        let body = ["content": content]
        try await send("/api/module/\(percentEncoded(name))", method: "PATCH", body: body)
    }

    public func deleteModule(name: String) async throws {
        try await send("/api/module/\(percentEncoded(name))", method: "DELETE")
    }

    // MARK: - Artifacts / Sync

    public func artifacts() async throws -> [SubStoreArtifact] {
        try await get("/api/artifacts", as: SubStoreArtifactsResponse.self).data
    }

    public func createArtifact(_ artifact: SubStoreArtifact) async throws -> SubStoreArtifact {
        try await send("/api/artifacts", method: "POST", body: artifact, as: SubStoreEnvelope<SubStoreArtifact>.self).data
    }

    public func updateArtifact(name: String, _ artifact: SubStoreArtifact) async throws -> SubStoreArtifact {
        try await send("/api/artifact/\(percentEncoded(name))", method: "PATCH", body: artifact, as: SubStoreEnvelope<SubStoreArtifact>.self).data
    }

    public func deleteArtifact(name: String) async throws {
        try await send("/api/artifact/\(percentEncoded(name))", method: "DELETE")
    }

    public func syncArtifacts() async throws {
        try await send("/api/sync/artifacts", method: "GET")
    }

    public func syncArtifact(name: String) async throws {
        try await send("/api/sync/artifact/\(percentEncoded(name))", method: "GET")
    }

    // MARK: - Tokens

    public func tokens() async throws -> [SubStoreShareToken] {
        try await get("/api/tokens", as: SubStoreTokensResponse.self).data
    }

    public func createToken(type: String, name: String, expiresAt: Int64?) async throws -> SubStoreShareToken {
        var body: [String: JSONValue] = [
            "type": .string(type),
            "name": .string(name)
        ]
        if let expiresAt {
            body["exp"] = .int(Int(expiresAt))
        }
        return try await send("/api/tokens", method: "POST", body: body, as: SubStoreEnvelope<SubStoreShareToken>.self).data
    }

    public func deleteToken(token: String) async throws {
        try await send("/api/tokens/\(percentEncoded(token))", method: "DELETE")
    }

    // MARK: - Archives

    public func archives() async throws -> [SubStoreArchive] {
        try await get("/api/archives", as: SubStoreArchivesResponse.self).data
    }

    public func deleteArchive(type: String, name: String, time: Int64) async throws {
        let path = "/api/archives/\(percentEncoded(type))/\(percentEncoded(name))/\(time)"
        try await send(path, method: "DELETE")
    }

    public func restoreArchive(type: String, name: String, time: Int64) async throws {
        let path = "/api/archives/\(percentEncoded(type))/\(percentEncoded(name))/\(time)/restore"
        try await send(path, method: "POST")
    }

    // MARK: - Settings

    public func settings() async throws -> SubStoreSettings {
        try await get("/api/settings", as: SubStoreSettingsResponse.self).data
    }

    public func updateSettings(_ settings: SubStoreSettings) async throws -> SubStoreSettings {
        try await send("/api/settings", method: "PATCH", body: settings.raw, as: SubStoreSettingsResponse.self).data
    }

    // MARK: - Misc

    public func gistBackupAction(_ action: String) async throws {
        try await send("/api/utils/backup/\(percentEncoded(action))", method: "GET")
    }

    public func logs(limit: Int = 100) async throws -> [SubStoreLogEntry] {
        let response = try await get("/api/logs?limit=\(limit)", as: SubStoreLogsResponse.self)
        return response.data
    }

    // MARK: - Path helpers

    private func subPath(_ name: String) -> String {
        "/api/sub/\(percentEncoded(name))"
    }

    private func collectionPath(_ name: String) -> String {
        "/api/collection/\(percentEncoded(name))"
    }

    private func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send(path, method: "GET", as: type)
    }

    private func send<Body: Encodable, T: Decodable>(
        _ path: String,
        method: String,
        query: String? = nil,
        body: Body,
        as type: T.Type
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, query: query, body: body)
        return try await execute(request, as: T.self)
    }

    private func send<Body: Encodable>(
        _ path: String,
        method: String,
        query: String? = nil,
        body: Body
    ) async throws {
        let request = try makeRequest(path: path, method: method, query: query, body: body)
        try await executeDiscardingBody(request)
    }

    private func send(
        _ path: String,
        method: String,
        query: String? = nil
    ) async throws {
        let request = try makeRequest(path: path, method: method, query: query, body: Optional<Bool>.none)
        try await executeDiscardingBody(request)
    }

    private func executeDiscardingBody(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.controllerResponse(http.statusCode, bodyText)
        }
    }

    private func send<T: Decodable>(
        _ path: String,
        method: String,
        query: String? = nil,
        as type: T.Type
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, query: query, body: Optional<Bool>.none)
        return try await execute(request, as: type)
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        query: String?,
        body: Body?
    ) throws -> URLRequest {
        var components = URLComponents()
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.path = trimmedPath
        if let query {
            components.percentEncodedQuery = query
        }

        guard let relativeURL = components.url(relativeTo: baseURL)?.absoluteURL else {
            throw KumoError.invalidArguments("Invalid Sub-Store URL for \(path)")
        }

        var request = URLRequest(url: relativeURL, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.subStore.encode(body)
        }
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.controllerResponse(http.statusCode, bodyText)
        }

        do {
            return try JSONDecoder.subStore.decode(T.self, from: data)
        } catch {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.commandFailed("Sub-Store response decoding failed: \(error.localizedDescription). Body: \(bodyText)")
        }
    }
}

public struct SubStoreEnvelope<T: Decodable>: Decodable {
    public var data: T

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        self.data = try container.decode(T.self, forKey: .data)
    }
}

private struct SubStoreSubscriptionsResponse: Decodable {
    var data: [SubStoreSubscription]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap(decodeSubscription)
    }
}

private struct SubStoreCollectionsResponse: Decodable {
    var data: [SubStoreCollection]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap(decodeCollection)
    }
}

private struct SubStoreFilesResponse: Decodable {
    var data: [SubStoreFile]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap { decodeJSON($0, as: SubStoreFile.self) }
    }
}

private struct SubStoreModulesResponse: Decodable {
    var data: [SubStoreModule]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap { decodeJSON($0, as: SubStoreModule.self) }
    }
}

private struct SubStoreArtifactsResponse: Decodable {
    var data: [SubStoreArtifact]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap { decodeJSON($0, as: SubStoreArtifact.self) }
    }
}

private struct SubStoreTokensResponse: Decodable {
    var data: [SubStoreShareToken]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap { decodeJSON($0, as: SubStoreShareToken.self) }
    }
}

private struct SubStoreArchivesResponse: Decodable {
    var data: [SubStoreArchive]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap { decodeJSON($0, as: SubStoreArchive.self) }
    }
}

private struct SubStoreSettingsResponse: Decodable {
    var data: SubStoreSettings

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        if let dict = try? container.decode([String: JSONValue].self, forKey: .data) {
            self.data = SubStoreSettings(raw: dict)
        } else {
            self.data = SubStoreSettings()
        }
    }
}

private struct SubStoreLogsResponse: Decodable {
    var data: [SubStoreLogEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([JSONValue].self, forKey: .data)
        self.data = raw.compactMap { decodeJSON($0, as: SubStoreLogEntry.self) }
    }
}

private struct SubStorePreviewResponse: Decodable {
    var data: SubStorePreviewResult

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SubStoreEnvelopeKeys.self)
        let raw = try container.decode([String: JSONValue].self, forKey: .data)
        let original = raw["original"]?.arrayValue ?? []
        let processed = raw["processed"]?.arrayValue ?? []
        self.data = SubStorePreviewResult(original: original, processed: processed)
    }
}

// Some endpoints return SubStoreFlow directly under `data`. Others (like flow info) return at top level.
// Handle both by using a shim decoder.
extension SubStoreFlow {
    public init(envelopedFrom data: Data) throws {
        if let envelope = try? JSONDecoder.subStore.decode(SubStoreFlowEnvelope.self, from: data) {
            self = envelope.data
            return
        }
        self = try JSONDecoder.subStore.decode(SubStoreFlow.self, from: data)
    }
}

private struct SubStoreFlowEnvelope: Decodable {
    var data: SubStoreFlow
}

public enum SubStoreEnvelopeKeys: String, CodingKey {
    case status
    case data
    case message
    case error
    case type
}

private func decodeSubscription(_ value: JSONValue) -> SubStoreSubscription? {
    decodeJSON(value, as: SubStoreSubscription.self)
}

private func decodeCollection(_ value: JSONValue) -> SubStoreCollection? {
    decodeJSON(value, as: SubStoreCollection.self)
}

private func decodeJSON<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
    guard let data = try? JSONEncoder.subStore.encode(value) else { return nil }
    return try? JSONDecoder.subStore.decode(T.self, from: data)
}

// MARK: - Coder helpers

extension JSONEncoder {
    /// Encoder used for Sub-Store payloads. Stable key order so PATCH bodies are
    /// deterministic and easy to inspect when debugging.
    public static var subStore: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    public static var subStore: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

// MARK: - Sub-Store decoding for flow (also has "expire" alias)

public extension SubStoreClient {
    /// Lower-level helper to GET flow info using the explicit envelope variant.
    /// Used by tests and manual inspections; production code should call
    /// `subscriptionFlow(name:)` instead.
    func rawSubscriptionFlow(name: String) async throws -> Data {
        let request = try makeRequest(
            path: "/api/sub/flow/\(percentEncoded(name))",
            method: "GET",
            query: nil,
            body: Optional<Bool>.none
        )
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw KumoError.controllerResponse(http.statusCode, bodyText)
        }
        return data
    }
}

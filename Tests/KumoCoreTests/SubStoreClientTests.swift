import XCTest
@testable import KumoCoreKit

final class SubStoreClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        SubStoreMockURLProtocol.responses = [:]
        SubStoreMockURLProtocol.requests = []
    }

    func testListSubscriptionsDecodesEnvelopeArray() async throws {
        let payload = """
        {"status":"success","data":[
          {"name":"sub-a","displayName":"Sub A","source":"remote","url":"https://example.com/a","tag":["fast"]},
          {"name":"sub-b","source":"local","content":"# yaml"}
        ]}
        """
        SubStoreMockURLProtocol.responses["/api/subs"] = .json(payload)
        let client = makeClient()

        let subscriptions = try await client.subscriptions()

        XCTAssertEqual(subscriptions.count, 2)
        XCTAssertEqual(subscriptions[0].name, "sub-a")
        XCTAssertEqual(subscriptions[0].resolvedDisplayName, "Sub A")
        XCTAssertEqual(subscriptions[0].tag, ["fast"])
        XCTAssertEqual(subscriptions[1].downloadPath, "/download/sub-b")
        XCTAssertTrue(subscriptions[1].isLocal)
    }

    func testGetCollectionUnwrapsEnvelope() async throws {
        let payload = """
        {"status":"success","data":{"name":"col-1","subscriptions":["sub-a","sub-b"],"subscriptionTags":["fast"]}}
        """
        SubStoreMockURLProtocol.responses["/api/collection/col-1"] = .json(payload)
        let client = makeClient()

        let collection = try await client.collection(name: "col-1")

        XCTAssertEqual(collection.name, "col-1")
        XCTAssertEqual(collection.subscriptions, ["sub-a", "sub-b"])
        XCTAssertEqual(collection.subscriptionTags, ["fast"])
    }

    func testFlowDecodesExpireAlias() async throws {
        let payload = """
        {"status":"success","data":{"upload":1024,"download":2048,"total":1048576,"expire":1700000000}}
        """
        SubStoreMockURLProtocol.responses["/api/sub/flow/sub-a"] = .json(payload)
        let client = makeClient()

        let flow = try await client.subscriptionFlow(name: "sub-a")

        XCTAssertEqual(flow.upload, 1024)
        XCTAssertEqual(flow.download, 2048)
        XCTAssertEqual(flow.total, 1_048_576)
        XCTAssertEqual(flow.expires, 1_700_000_000)
        XCTAssertEqual(flow.usedFraction, Double(3072) / Double(1_048_576), accuracy: 0.0001)
    }

    func testDeleteSubscriptionWithArchiveQuery() async throws {
        SubStoreMockURLProtocol.responses["/api/sub/sub-a"] = .empty
        let client = makeClient()

        try await client.deleteSubscription(name: "sub-a", archive: true)

        let recorded = SubStoreMockURLProtocol.requests.last
        XCTAssertEqual(recorded?.httpMethod, "DELETE")
        XCTAssertEqual(recorded?.url?.path, "/api/sub/sub-a")
        XCTAssertEqual(recorded?.url?.query, "mode=archive")
    }

    func testCreateSubscriptionEncodesBody() async throws {
        let payload = """
        {"status":"success","data":{"name":"sub-new","source":"remote","url":"https://example.com/new"}}
        """
        SubStoreMockURLProtocol.responses["/api/subs"] = .json(payload)
        let client = makeClient()

        let new = SubStoreSubscription(
            name: "sub-new",
            source: "remote",
            url: "https://example.com/new"
        )
        let created = try await client.createSubscription(new)

        let recorded = SubStoreMockURLProtocol.requests.last
        XCTAssertEqual(recorded?.httpMethod, "POST")
        XCTAssertEqual(recorded?.url?.path, "/api/subs")
        let body = recorded?.bodyData ?? Data()
        let string = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(string.contains("\"name\":\"sub-new\""), "body was: \(string)")
        XCTAssertTrue(string.contains("https:") && string.contains("example.com"), "body was: \(string)")
        XCTAssertEqual(created.name, "sub-new")
    }

    func testReplaceSubscriptionsSendsArrayBody() async throws {
        SubStoreMockURLProtocol.responses["/api/subs"] = .empty
        let client = makeClient()
        let list = [
            SubStoreSubscription(name: "a"),
            SubStoreSubscription(name: "b")
        ]

        try await client.replaceSubscriptions(list)

        let recorded = SubStoreMockURLProtocol.requests.last
        XCTAssertEqual(recorded?.httpMethod, "PUT")
        XCTAssertEqual(recorded?.url?.path, "/api/subs")
    }

    func testDownloadPathHelpers() {
        let sub = SubStoreSubscription(name: "with space")
        let collection = SubStoreCollection(name: "组合 A")
        XCTAssertEqual(sub.downloadPath, "/download/with%20space")
        XCTAssertEqual(collection.downloadPath, "/download/collection/%E7%BB%84%E5%90%88%20A")
    }

    private func makeClient() -> SubStoreClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubStoreMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return SubStoreClient(baseURL: URL(string: "http://127.0.0.1:38324")!, session: session)
    }
}

// MARK: - URLProtocol stub

extension URLRequest {
    /// `URLProtocol` strips `httpBody` and exposes a stream instead. This
    /// helper drains the stream when present.
    var bodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class SubStoreMockURLProtocol: URLProtocol {
    enum Response {
        case json(String)
        case empty
        case status(Int, String)
    }

    nonisolated(unsafe) static var responses: [String: Response] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let path = request.url?.path ?? ""
        let response = Self.responses[path] ?? .status(404, "{}")

        switch response {
        case .json(let payload):
            sendResponse(statusCode: 200, body: payload)
        case .empty:
            sendResponse(statusCode: 200, body: "{\"status\":\"success\"}")
        case .status(let code, let body):
            sendResponse(statusCode: code, body: body)
        }
    }

    override func stopLoading() {}

    private func sendResponse(statusCode: Int, body: String) {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

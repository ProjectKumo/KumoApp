import XCTest
@testable import KumoCoreKit

final class MihomoControllerClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testProxyGroupsMapControllerResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/proxies")
            let data = Data(
                """
                {
                  "proxies": {
                    "Proxy": { "type": "Selector", "now": "HK", "all": ["HK", "US"] },
                    "HK": { "type": "Shadowsocks", "history": [{ "delay": 120 }] },
                    "US": { "type": "Shadowsocks", "history": [{ "delay": 200 }] },
                    "Hidden": { "type": "Selector", "hidden": true, "all": ["HK"] }
                  }
                }
                """.utf8
            )
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = MihomoControllerClient(session: mockSession())

        let groups = try await client.proxyGroups()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "Proxy")
        XCTAssertEqual(groups.first?.selectedProxyName, "HK")
        XCTAssertEqual(groups.first?.proxies.map(\.delay), [120, 200])
    }

    func testConnectionsMapControllerResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/connections")
            let data = Data(
                """
                {
                  "connections": [
                    {
                      "id": "abc",
                      "metadata": { "host": "example.com", "process": "Safari" },
                      "rule": "MATCH",
                      "chains": ["Proxy", "HK"],
                      "upload": 10,
                      "download": 20
                    }
                  ]
                }
                """.utf8
            )
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = MihomoControllerClient(session: mockSession())

        let connections = try await client.connections()

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.id, "abc")
        XCTAssertEqual(connections.first?.host, "example.com")
        XCTAssertEqual(connections.first?.process, "Safari")
        XCTAssertEqual(connections.first?.chain, ["Proxy", "HK"])
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: KumoError.invalidArguments("Missing mock request handler."))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

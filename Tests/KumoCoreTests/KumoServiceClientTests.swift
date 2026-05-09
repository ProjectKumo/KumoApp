import XCTest
@testable import KumoCoreKit

final class KumoServiceClientTests: XCTestCase {
    func testSignedRequestIncludesCanonicalAuthHeaders() {
        let signer = KumoServiceRequestSigner(
            credentials: KumoServiceCredentials(keyID: "test-key", sharedSecret: "secret")
        )
        let request = signer.signedRequest(
            method: "post",
            path: "/core/start",
            body: Data("{}".utf8),
            timestamp: Date(timeIntervalSince1970: 0),
            nonce: "nonce"
        )

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/core/start")
        XCTAssertEqual(request.headers["X-Kumo-Auth-Version"], "1")
        XCTAssertEqual(request.headers["X-Kumo-Key-ID"], "test-key")
        XCTAssertEqual(request.headers["X-Kumo-Nonce"], "nonce")
        XCTAssertNotNil(request.headers["X-Kumo-Content-SHA256"])
        XCTAssertNotNil(request.headers["X-Kumo-Signature"])
    }
}

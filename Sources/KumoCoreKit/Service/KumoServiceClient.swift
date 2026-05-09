import CryptoKit
import Foundation

public struct KumoServiceEndpoint: Codable, Equatable, Sendable {
    public var socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }
}

public struct KumoServiceCredentials: Codable, Equatable, Sendable {
    public var keyID: String
    public var sharedSecret: String

    public init(keyID: String, sharedSecret: String) {
        self.keyID = keyID
        self.sharedSecret = sharedSecret
    }
}

public struct KumoServiceSignedRequest: Codable, Equatable, Sendable {
    public var method: String
    public var path: String
    public var body: Data
    public var headers: [String: String]

    public init(method: String, path: String, body: Data = Data(), headers: [String: String]) {
        self.method = method
        self.path = path
        self.body = body
        self.headers = headers
    }
}

public struct KumoServiceRequestSigner: Sendable {
    public var credentials: KumoServiceCredentials

    public init(credentials: KumoServiceCredentials) {
        self.credentials = credentials
    }

    public func signedRequest(
        method: String,
        path: String,
        query: String = "",
        body: Data = Data(),
        timestamp: Date = Date(),
        nonce: String = UUID().uuidString
    ) -> KumoServiceSignedRequest {
        let canonicalMethod = method.uppercased()
        let bodyHash = SHA256.hash(data: body).hexString
        let timestampValue = Self.timestampString(from: timestamp)
        let canonical = [
            "KUMO-AUTH-V1",
            timestampValue,
            nonce,
            credentials.keyID,
            canonicalMethod,
            path.isEmpty ? "/" : path,
            query,
            bodyHash
        ].joined(separator: "\n")
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(canonical.utf8),
            using: SymmetricKey(data: Data(credentials.sharedSecret.utf8))
        ).hexString

        return KumoServiceSignedRequest(
            method: canonicalMethod,
            path: path,
            body: body,
            headers: [
                "X-Kumo-Auth-Version": "1",
                "X-Kumo-Key-ID": credentials.keyID,
                "X-Kumo-Timestamp": timestampValue,
                "X-Kumo-Nonce": nonce,
                "X-Kumo-Content-SHA256": bodyHash,
                "X-Kumo-Signature": signature
            ]
        )
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct KumoServiceClient: Sendable {
    public var endpoint: KumoServiceEndpoint
    public var signer: KumoServiceRequestSigner

    public init(endpoint: KumoServiceEndpoint, credentials: KumoServiceCredentials) {
        self.endpoint = endpoint
        self.signer = KumoServiceRequestSigner(credentials: credentials)
    }

    public func signedRequest(method: String, path: String, body: Data = Data()) -> KumoServiceSignedRequest {
        signer.signedRequest(method: method, path: path, body: body)
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension HMAC<SHA256>.MAC {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

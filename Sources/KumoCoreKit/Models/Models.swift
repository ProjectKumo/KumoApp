import Foundation

public enum OutboundMode: String, Codable, CaseIterable, Sendable {
    case rule
    case global
    case direct

    public var displayName: String {
        switch self {
        case .rule: "Rule"
        case .global: "Global"
        case .direct: "Direct"
        }
    }
}

public enum CoreRunState: String, Codable, Sendable {
    case stopped
    case starting
    case running
    case failed
}

public struct ControllerEndpoint: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var secret: String

    public init(host: String = "127.0.0.1", port: Int = 9097, secret: String = "") {
        self.host = host
        self.port = port
        self.secret = secret
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

public struct ProxyPortConfiguration: Codable, Equatable, Sendable {
    public var mixedPort: Int

    public init(mixedPort: Int = 7890) {
        self.mixedPort = mixedPort
    }
}

public struct CoreStatus: Codable, Equatable, Sendable {
    public var state: CoreRunState
    public var pid: Int32?
    public var corePath: String?
    public var mode: OutboundMode
    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
    public var systemProxyEnabled: Bool
    public var message: String?

    public init(
        state: CoreRunState = .stopped,
        pid: Int32? = nil,
        corePath: String? = nil,
        mode: OutboundMode = .rule,
        endpoint: ControllerEndpoint = ControllerEndpoint(),
        proxyPorts: ProxyPortConfiguration = ProxyPortConfiguration(),
        systemProxyEnabled: Bool = false,
        message: String? = nil
    ) {
        self.state = state
        self.pid = pid
        self.corePath = corePath
        self.mode = mode
        self.endpoint = endpoint
        self.proxyPorts = proxyPorts
        self.systemProxyEnabled = systemProxyEnabled
        self.message = message
    }
}

public struct CoreCandidate: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var sourceDescription: String

    public init(name: String, path: String, sourceDescription: String) {
        self.name = name
        self.path = path
        self.sourceDescription = sourceDescription
    }
}

public enum ProfileSource: Codable, Equatable, Sendable {
    case remote(URL)
    case file(URL)
    case inline
}

public struct Profile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var source: ProfileSource
    public var rawYAML: String
    public var updatedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        source: ProfileSource,
        rawYAML: String,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.rawYAML = rawYAML
        self.updatedAt = updatedAt
    }
}

public enum ProfileKind: String, Codable, Equatable, Sendable {
    case local
    case remote
    case inline
}

public struct SubscriptionUserInfo: Codable, Equatable, Sendable {
    public var upload: Int
    public var download: Int
    public var total: Int
    public var expire: Int?

    public init(upload: Int = 0, download: Int = 0, total: Int = 0, expire: Int? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }
}

public struct ProfileSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sourceDescription: String
    public var updatedAt: Date?
    public var isCurrent: Bool
    public var kind: ProfileKind
    public var remoteURL: URL?
    public var homeURL: URL?
    public var autoUpdate: Bool
    public var useProxy: Bool
    public var updateIntervalSeconds: Int?
    public var subscriptionUserInfo: SubscriptionUserInfo?

    public init(
        id: String,
        name: String,
        sourceDescription: String,
        updatedAt: Date? = nil,
        isCurrent: Bool = false,
        kind: ProfileKind = .local,
        remoteURL: URL? = nil,
        homeURL: URL? = nil,
        autoUpdate: Bool = true,
        useProxy: Bool = false,
        updateIntervalSeconds: Int? = nil,
        subscriptionUserInfo: SubscriptionUserInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceDescription = sourceDescription
        self.updatedAt = updatedAt
        self.isCurrent = isCurrent
        self.kind = kind
        self.remoteURL = remoteURL
        self.homeURL = homeURL
        self.autoUpdate = autoUpdate
        self.useProxy = useProxy
        self.updateIntervalSeconds = updateIntervalSeconds
        self.subscriptionUserInfo = subscriptionUserInfo
    }
}

public struct ProxyNode: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var delay: Int?

    public init(name: String, delay: Int? = nil) {
        self.name = name
        self.delay = delay
    }
}

public struct CoreConfigurationSnapshot: Codable, Equatable, Sendable {
    public var version: String?
    public var mode: OutboundMode
    public var mixedPort: Int
    public var logLevel: String
    public var allowLAN: Bool
    public var tunEnabled: Bool
    public var dnsEnabled: Bool
    public var snifferEnabled: Bool

    public init(
        version: String? = nil,
        mode: OutboundMode = .rule,
        mixedPort: Int = 7890,
        logLevel: String = "info",
        allowLAN: Bool = false,
        tunEnabled: Bool = false,
        dnsEnabled: Bool = false,
        snifferEnabled: Bool = false
    ) {
        self.version = version
        self.mode = mode
        self.mixedPort = mixedPort
        self.logLevel = logLevel
        self.allowLAN = allowLAN
        self.tunEnabled = tunEnabled
        self.dnsEnabled = dnsEnabled
        self.snifferEnabled = snifferEnabled
    }
}

public struct RuleEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var payload: String
    public var proxy: String

    public init(id: String, type: String, payload: String, proxy: String) {
        self.id = id
        self.type = type
        self.payload = payload
        self.proxy = proxy
    }
}

public struct ConnectionEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var host: String
    public var process: String?
    public var rule: String?
    public var chain: [String]
    public var upload: Int
    public var download: Int
    public var uploadSpeed: Int
    public var downloadSpeed: Int
    public var startedAt: String?

    public init(
        id: String,
        host: String,
        process: String? = nil,
        rule: String? = nil,
        chain: [String] = [],
        upload: Int = 0,
        download: Int = 0,
        uploadSpeed: Int = 0,
        downloadSpeed: Int = 0,
        startedAt: String? = nil
    ) {
        self.id = id
        self.host = host
        self.process = process
        self.rule = rule
        self.chain = chain
        self.upload = upload
        self.download = download
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.startedAt = startedAt
    }
}

public struct LogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var level: String
    public var message: String

    public init(id: String, level: String = "info", message: String) {
        self.id = id
        self.level = level
        self.message = message
    }
}

public struct ProxyGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var selectedProxyName: String?
    public var proxies: [ProxyNode]
    public var testURL: String?

    public init(
        name: String,
        selectedProxyName: String? = nil,
        proxies: [ProxyNode] = [],
        testURL: String? = nil
    ) {
        self.name = name
        self.selectedProxyName = selectedProxyName
        self.proxies = proxies
        self.testURL = testURL
    }
}

public struct CLIResponse<T: Encodable>: Encodable {
    public var ok: Bool
    public var data: T?
    public var error: String?

    public init(ok: Bool, data: T? = nil, error: String? = nil) {
        self.ok = ok
        self.data = data
        self.error = error
    }
}

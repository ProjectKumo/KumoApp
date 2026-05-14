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

public enum CoreReadiness: String, Codable, Sendable {
    case processLaunched
    case controllerReady
    case providersReady
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

public struct GeoDataSettings: Codable, Equatable, Sendable {
    public var geoIPURL: String
    public var geoSiteURL: String
    public var mmdbURL: String
    public var asnURL: String
    public var autoUpdate: Bool
    public var updateIntervalHours: Int
    public var usesDatMode: Bool

    public init(
        geoIPURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat",
        geoSiteURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat",
        mmdbURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb",
        asnURL: String = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb",
        autoUpdate: Bool = false,
        updateIntervalHours: Int = 24,
        usesDatMode: Bool = false
    ) {
        self.geoIPURL = geoIPURL
        self.geoSiteURL = geoSiteURL
        self.mmdbURL = mmdbURL
        self.asnURL = asnURL
        self.autoUpdate = autoUpdate
        self.updateIntervalHours = updateIntervalHours
        self.usesDatMode = usesDatMode
    }
}

public struct CoreRuntimeSettings: Codable, Equatable, Sendable {
    public var mixedPort: Int
    public var allowLAN: Bool
    public var logLevel: String
    public var ipv6: Bool
    public var findProcessMode: String
    public var geoData: GeoDataSettings
    public var tun: TunSettings?

    public init(
        mixedPort: Int = 7890,
        allowLAN: Bool = false,
        logLevel: String = "info",
        ipv6: Bool = false,
        findProcessMode: String = "always",
        geoData: GeoDataSettings = GeoDataSettings(),
        tun: TunSettings? = nil
    ) {
        self.mixedPort = mixedPort
        self.allowLAN = allowLAN
        self.logLevel = logLevel
        self.ipv6 = ipv6
        self.findProcessMode = findProcessMode
        self.geoData = geoData
        self.tun = tun
    }

    private enum CodingKeys: String, CodingKey {
        case mixedPort
        case allowLAN
        case logLevel
        case ipv6
        case findProcessMode
        case geoData
        case tun
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mixedPort: try container.decode(Int.self, forKey: .mixedPort),
            allowLAN: try container.decode(Bool.self, forKey: .allowLAN),
            logLevel: try container.decode(String.self, forKey: .logLevel),
            ipv6: try container.decode(Bool.self, forKey: .ipv6),
            findProcessMode: try container.decodeIfPresent(String.self, forKey: .findProcessMode) ?? "always",
            geoData: try container.decode(GeoDataSettings.self, forKey: .geoData),
            tun: try container.decodeIfPresent(TunSettings.self, forKey: .tun)
        )
    }
}

public struct TunSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var stack: String
    public var autoRoute: Bool
    public var autoRedirect: Bool
    public var autoDetectInterface: Bool
    public var strictRoute: Bool
    public var disableICMPForwarding: Bool
    public var dnsHijack: [String]
    public var routeExcludeAddress: [String]
    public var mtu: Int
    public var device: String?
    public var dnsEnabled: Bool
    public var dnsEnhancedMode: String
    public var fakeIPRange: String
    public var nameservers: [String]

    public init(
        isEnabled: Bool = false,
        stack: String = "mixed",
        autoRoute: Bool = true,
        autoRedirect: Bool = false,
        autoDetectInterface: Bool = true,
        strictRoute: Bool = false,
        disableICMPForwarding: Bool = false,
        dnsHijack: [String] = ["any:53"],
        routeExcludeAddress: [String] = [],
        mtu: Int = 1500,
        device: String? = nil,
        dnsEnabled: Bool = true,
        dnsEnhancedMode: String = "fake-ip",
        fakeIPRange: String = "198.18.0.1/16",
        nameservers: [String] = ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"]
    ) {
        self.isEnabled = isEnabled
        self.stack = stack
        self.autoRoute = autoRoute
        self.autoRedirect = autoRedirect
        self.autoDetectInterface = autoDetectInterface
        self.strictRoute = strictRoute
        self.disableICMPForwarding = disableICMPForwarding
        self.dnsHijack = dnsHijack
        self.routeExcludeAddress = routeExcludeAddress
        self.mtu = mtu
        self.device = device
        self.dnsEnabled = dnsEnabled
        self.dnsEnhancedMode = dnsEnhancedMode
        self.fakeIPRange = fakeIPRange
        self.nameservers = nameservers
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case stack
        case autoRoute
        case autoRedirect
        case autoDetectInterface
        case strictRoute
        case disableICMPForwarding
        case dnsHijack
        case routeExcludeAddress
        case mtu
        case device
        case dnsEnabled
        case dnsEnhancedMode
        case fakeIPRange
        case nameservers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TunSettings()
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled,
            stack: try container.decodeIfPresent(String.self, forKey: .stack) ?? defaults.stack,
            autoRoute: try container.decodeIfPresent(Bool.self, forKey: .autoRoute) ?? defaults.autoRoute,
            autoRedirect: try container.decodeIfPresent(Bool.self, forKey: .autoRedirect) ?? defaults.autoRedirect,
            autoDetectInterface: try container.decodeIfPresent(Bool.self, forKey: .autoDetectInterface) ?? defaults.autoDetectInterface,
            strictRoute: try container.decodeIfPresent(Bool.self, forKey: .strictRoute) ?? defaults.strictRoute,
            disableICMPForwarding: try container.decodeIfPresent(Bool.self, forKey: .disableICMPForwarding) ?? defaults.disableICMPForwarding,
            dnsHijack: try container.decodeIfPresent([String].self, forKey: .dnsHijack) ?? defaults.dnsHijack,
            routeExcludeAddress: try container.decodeIfPresent([String].self, forKey: .routeExcludeAddress) ?? defaults.routeExcludeAddress,
            mtu: try container.decodeIfPresent(Int.self, forKey: .mtu) ?? defaults.mtu,
            device: try container.decodeIfPresent(String.self, forKey: .device) ?? defaults.device,
            dnsEnabled: try container.decodeIfPresent(Bool.self, forKey: .dnsEnabled) ?? defaults.dnsEnabled,
            dnsEnhancedMode: try container.decodeIfPresent(String.self, forKey: .dnsEnhancedMode) ?? defaults.dnsEnhancedMode,
            fakeIPRange: try container.decodeIfPresent(String.self, forKey: .fakeIPRange) ?? defaults.fakeIPRange,
            nameservers: try container.decodeIfPresent([String].self, forKey: .nameservers) ?? defaults.nameservers
        )
    }
}

public struct ServiceModeStatus: Codable, Equatable, Sendable {
    public var isInstalled: Bool
    public var isRunning: Bool
    public var isAvailable: Bool
    public var isCurrentProcessPrivileged: Bool
    public var socketPath: String
    public var message: String?

    public init(
        isInstalled: Bool = false,
        isRunning: Bool = false,
        isAvailable: Bool = false,
        isCurrentProcessPrivileged: Bool = false,
        socketPath: String = "",
        message: String? = nil
    ) {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.isAvailable = isAvailable
        self.isCurrentProcessPrivileged = isCurrentProcessPrivileged
        self.socketPath = socketPath
        self.message = message
    }

    public var canManageTun: Bool {
        isAvailable || isCurrentProcessPrivileged
    }
}

public struct TunStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var isRunning: Bool
    public var requiresService: Bool
    public var lastError: String?

    public init(
        isEnabled: Bool = false,
        isRunning: Bool = false,
        requiresService: Bool = true,
        lastError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.isRunning = isRunning
        self.requiresService = requiresService
        self.lastError = lastError
    }
}

public enum SystemProxyMode: String, Codable, CaseIterable, Sendable {
    case manual
    case pac

    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .pac: "PAC"
        }
    }
}

public struct SystemProxySettings: Codable, Equatable, Sendable {
    public var networkService: String
    public var host: String
    public var port: Int
    public var mode: SystemProxyMode
    public var bypassList: [String]
    public var pacScript: String

    public init(
        networkService: String = "Wi-Fi",
        host: String = "127.0.0.1",
        port: Int = 7890,
        mode: SystemProxyMode = .manual,
        bypassList: [String] = SystemProxySettings.defaultBypassList,
        pacScript: String = SystemProxySettings.defaultPACScript
    ) {
        self.networkService = networkService
        self.host = host
        self.port = port
        self.mode = mode
        self.bypassList = bypassList
        self.pacScript = pacScript
    }

    public static let defaultBypassList = [
        "127.0.0.1/8",
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "localhost",
        "*.local",
        "<local>"
    ]

    public static let defaultPACScript = """
    function FindProxyForURL(url, host) {
      return "PROXY 127.0.0.1:%mixed-port%; SOCKS5 127.0.0.1:%mixed-port%; DIRECT;";
    }
    """
}

public struct SystemProxySnapshot: Codable, Equatable, Sendable {
    public var networkService: String
    public var capturedAt: Date
    public var webProxy: String
    public var secureWebProxy: String
    public var socksProxy: String
    public var bypassDomains: String

    public init(
        networkService: String,
        capturedAt: Date = Date(),
        webProxy: String = "",
        secureWebProxy: String = "",
        socksProxy: String = "",
        bypassDomains: String = ""
    ) {
        self.networkService = networkService
        self.capturedAt = capturedAt
        self.webProxy = webProxy
        self.secureWebProxy = secureWebProxy
        self.socksProxy = socksProxy
        self.bypassDomains = bypassDomains
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
    public var runtimeSettings: CoreRuntimeSettings?
    public var systemProxySettings: SystemProxySettings?
    public var previousSystemProxySnapshot: SystemProxySnapshot?
    public var serviceModeStatus: ServiceModeStatus?
    public var tunStatus: TunStatus?
    public var readiness: CoreReadiness?
    public var message: String?

    public init(
        state: CoreRunState = .stopped,
        pid: Int32? = nil,
        corePath: String? = nil,
        mode: OutboundMode = .rule,
        endpoint: ControllerEndpoint = ControllerEndpoint(),
        proxyPorts: ProxyPortConfiguration = ProxyPortConfiguration(),
        systemProxyEnabled: Bool = false,
        runtimeSettings: CoreRuntimeSettings? = nil,
        systemProxySettings: SystemProxySettings? = nil,
        previousSystemProxySnapshot: SystemProxySnapshot? = nil,
        serviceModeStatus: ServiceModeStatus? = nil,
        tunStatus: TunStatus? = nil,
        readiness: CoreReadiness? = nil,
        message: String? = nil
    ) {
        self.state = state
        self.pid = pid
        self.corePath = corePath
        self.mode = mode
        self.endpoint = endpoint
        self.proxyPorts = proxyPorts
        self.systemProxyEnabled = systemProxyEnabled
        self.runtimeSettings = runtimeSettings
        self.systemProxySettings = systemProxySettings
        self.previousSystemProxySnapshot = previousSystemProxySnapshot
        self.serviceModeStatus = serviceModeStatus
        self.tunStatus = tunStatus
        self.readiness = readiness
        self.message = message
    }
}

public struct RuntimeEventEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var time: Date
    public var kind: String
    public var message: String

    public init(id: String = UUID().uuidString, time: Date = Date(), kind: String, message: String) {
        self.id = id
        self.time = time
        self.kind = kind
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
    public var isSubStoreManaged: Bool
    public var subStorePath: String?

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
        subscriptionUserInfo: SubscriptionUserInfo? = nil,
        isSubStoreManaged: Bool = false,
        subStorePath: String? = nil
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
        self.isSubStoreManaged = isSubStoreManaged
        self.subStorePath = subStorePath
    }
}

public struct ProxyNode: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String?
    public var delay: Int?
    /// ISO 3166-1 alpha-2 region code inferred from the upstream server IP,
    /// populated asynchronously by `ProxyGeoLookup`. UI uses this as a
    /// fallback when parsing the node's display name cannot determine the
    /// country. `nil` means "not yet looked up" or "lookup failed".
    public var detectedCountry: String?

    public init(
        name: String,
        type: String? = nil,
        delay: Int? = nil,
        detectedCountry: String? = nil
    ) {
        self.name = name
        self.type = type
        self.delay = delay
        self.detectedCountry = detectedCountry
    }
}

public struct CoreConfigurationSnapshot: Codable, Equatable, Sendable {
    public var version: String?
    public var mode: OutboundMode
    public var mixedPort: Int
    public var logLevel: String
    public var allowLAN: Bool
    public var ipv6: Bool
    public var geoData: GeoDataSettings
    public var tunEnabled: Bool
    public var dnsEnabled: Bool
    public var snifferEnabled: Bool

    public init(
        version: String? = nil,
        mode: OutboundMode = .rule,
        mixedPort: Int = 7890,
        logLevel: String = "info",
        allowLAN: Bool = false,
        ipv6: Bool = false,
        geoData: GeoDataSettings = GeoDataSettings(),
        tunEnabled: Bool = false,
        dnsEnabled: Bool = false,
        snifferEnabled: Bool = false
    ) {
        self.version = version
        self.mode = mode
        self.mixedPort = mixedPort
        self.logLevel = logLevel
        self.allowLAN = allowLAN
        self.ipv6 = ipv6
        self.geoData = geoData
        self.tunEnabled = tunEnabled
        self.dnsEnabled = dnsEnabled
        self.snifferEnabled = snifferEnabled
    }
}

public struct RuleEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var index: Int
    public var type: String
    public var payload: String
    public var proxy: String
    public var isEnabled: Bool
    public var hitCount: Int
    public var missCount: Int
    public var lastHit: String?
    public var lastMiss: String?
    public var size: Int

    public init(
        id: String,
        index: Int = 0,
        type: String,
        payload: String,
        proxy: String,
        isEnabled: Bool = true,
        hitCount: Int = 0,
        missCount: Int = 0,
        lastHit: String? = nil,
        lastMiss: String? = nil,
        size: Int = 0
    ) {
        self.id = id
        self.index = index
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.isEnabled = isEnabled
        self.hitCount = hitCount
        self.missCount = missCount
        self.lastHit = lastHit
        self.lastMiss = lastMiss
        self.size = size
    }

    public var hitRate: Double? {
        let total = hitCount + missCount
        guard total > 0 else { return nil }
        return Double(hitCount) / Double(total)
    }
}

public struct ConnectionEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var host: String
    public var process: String?
    public var processPath: String?
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
        processPath: String? = nil,
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
        self.processPath = processPath
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
    public var time: String?

    public init(id: String, level: String = "info", message: String, time: String? = nil) {
        self.id = id
        self.level = level
        self.message = message
        self.time = time
    }
}

public struct TrafficSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var upload: Int
    public var download: Int
    public var uploadSpeed: Int
    public var downloadSpeed: Int

    public init(
        id: String = UUID().uuidString,
        upload: Int = 0,
        download: Int = 0,
        uploadSpeed: Int = 0,
        downloadSpeed: Int = 0
    ) {
        self.id = id
        self.upload = upload
        self.download = download
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
    }
}

public struct MemorySnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var inUse: Int
    public var osLimit: Int

    public init(id: String = UUID().uuidString, inUse: Int = 0, osLimit: Int = 0) {
        self.id = id
        self.inUse = inUse
        self.osLimit = osLimit
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

public struct ProviderSubscriptionInfo: Codable, Equatable, Sendable {
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

public struct ProxyProviderEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var vehicleType: String
    public var updatedAt: String?
    public var proxyCount: Int
    public var subscriptionInfo: ProviderSubscriptionInfo?

    public init(
        name: String,
        vehicleType: String,
        updatedAt: String? = nil,
        proxyCount: Int = 0,
        subscriptionInfo: ProviderSubscriptionInfo? = nil
    ) {
        self.name = name
        self.vehicleType = vehicleType
        self.updatedAt = updatedAt
        self.proxyCount = proxyCount
        self.subscriptionInfo = subscriptionInfo
    }
}

public struct RuleProviderEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var vehicleType: String
    public var behavior: String
    public var format: String
    public var updatedAt: String?
    public var ruleCount: Int

    public init(
        name: String,
        vehicleType: String,
        behavior: String = "-",
        format: String = "-",
        updatedAt: String? = nil,
        ruleCount: Int = 0
    ) {
        self.name = name
        self.vehicleType = vehicleType
        self.behavior = behavior
        self.format = format
        self.updatedAt = updatedAt
        self.ruleCount = ruleCount
    }
}

public enum OverrideKind: String, Codable, CaseIterable, Sendable {
    case local
    case remote
}

public enum OverrideFormat: String, Codable, CaseIterable, Sendable {
    case yaml
    case javascript
}

public struct OverrideItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: OverrideKind
    public var format: OverrideFormat
    public var updatedAt: Date
    public var isGlobal: Bool
    public var remoteURL: URL?
    public var fingerprint: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: OverrideKind,
        format: OverrideFormat = .yaml,
        updatedAt: Date = Date(),
        isGlobal: Bool = false,
        remoteURL: URL? = nil,
        fingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.format = format
        self.updatedAt = updatedAt
        self.isGlobal = isGlobal
        self.remoteURL = remoteURL
        self.fingerprint = fingerprint
    }
}

public struct SubStoreStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var usesCustomBackend: Bool
    public var customBackendURL: URL?
    public var frontendDownloadURL: URL?
    public var backendDownloadURL: URL?
    public var localFrontendPath: String?
    public var localBackendPath: String?
    public var lastUpdatedAt: Date?
    public var backendPort: Int?
    public var frontendPort: Int?
    public var allowsLAN: Bool
    public var usesProxy: Bool
    public var host: String
    public var syncCron: String
    public var downloadCron: String
    public var uploadCron: String
    public var installedResourceVersion: String?
    public var lastResourceInstallAt: Date?
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case usesCustomBackend
        case customBackendURL
        case frontendDownloadURL
        case backendDownloadURL
        case localFrontendPath
        case localBackendPath
        case lastUpdatedAt
        case backendPort
        case frontendPort
        case allowsLAN
        case usesProxy
        case host
        case syncCron
        case downloadCron
        case uploadCron
        case installedResourceVersion
        case lastResourceInstallAt
        case lastError
    }

    public init(
        isEnabled: Bool = false,
        usesCustomBackend: Bool = false,
        customBackendURL: URL? = nil,
        frontendDownloadURL: URL? = nil,
        backendDownloadURL: URL? = nil,
        localFrontendPath: String? = nil,
        localBackendPath: String? = nil,
        lastUpdatedAt: Date? = nil,
        backendPort: Int? = nil,
        frontendPort: Int? = nil,
        allowsLAN: Bool = false,
        usesProxy: Bool = false,
        host: String = "127.0.0.1",
        syncCron: String = "",
        downloadCron: String = "",
        uploadCron: String = "",
        installedResourceVersion: String? = nil,
        lastResourceInstallAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.usesCustomBackend = usesCustomBackend
        self.customBackendURL = customBackendURL
        self.frontendDownloadURL = frontendDownloadURL
        self.backendDownloadURL = backendDownloadURL
        self.localFrontendPath = localFrontendPath
        self.localBackendPath = localBackendPath
        self.lastUpdatedAt = lastUpdatedAt
        self.backendPort = backendPort
        self.frontendPort = frontendPort
        self.allowsLAN = allowsLAN
        self.usesProxy = usesProxy
        self.host = host
        self.syncCron = syncCron
        self.downloadCron = downloadCron
        self.uploadCron = uploadCron
        self.installedResourceVersion = installedResourceVersion
        self.lastResourceInstallAt = lastResourceInstallAt
        self.lastError = lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SubStoreStatus()
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled,
            usesCustomBackend: try container.decodeIfPresent(Bool.self, forKey: .usesCustomBackend) ?? defaults.usesCustomBackend,
            customBackendURL: try container.decodeIfPresent(URL.self, forKey: .customBackendURL),
            frontendDownloadURL: try container.decodeIfPresent(URL.self, forKey: .frontendDownloadURL),
            backendDownloadURL: try container.decodeIfPresent(URL.self, forKey: .backendDownloadURL),
            localFrontendPath: try container.decodeIfPresent(String.self, forKey: .localFrontendPath),
            localBackendPath: try container.decodeIfPresent(String.self, forKey: .localBackendPath),
            lastUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt),
            backendPort: try container.decodeIfPresent(Int.self, forKey: .backendPort),
            frontendPort: try container.decodeIfPresent(Int.self, forKey: .frontendPort),
            allowsLAN: try container.decodeIfPresent(Bool.self, forKey: .allowsLAN) ?? defaults.allowsLAN,
            usesProxy: try container.decodeIfPresent(Bool.self, forKey: .usesProxy) ?? defaults.usesProxy,
            host: try container.decodeIfPresent(String.self, forKey: .host) ?? defaults.host,
            syncCron: try container.decodeIfPresent(String.self, forKey: .syncCron) ?? defaults.syncCron,
            downloadCron: try container.decodeIfPresent(String.self, forKey: .downloadCron) ?? defaults.downloadCron,
            uploadCron: try container.decodeIfPresent(String.self, forKey: .uploadCron) ?? defaults.uploadCron,
            installedResourceVersion: try container.decodeIfPresent(String.self, forKey: .installedResourceVersion),
            lastResourceInstallAt: try container.decodeIfPresent(Date.self, forKey: .lastResourceInstallAt),
            lastError: try container.decodeIfPresent(String.self, forKey: .lastError)
        )
    }
}

public enum SubStoreBundleKind: String, Codable, CaseIterable, Sendable {
    case frontend
    case backend
}

public struct SubStoreResourceManifest: Codable, Equatable, Sendable {
    public var version: String
    public var nodeExecutableRelativePath: String
    public var backendBundleRelativePath: String

    public init(
        version: String = "0",
        nodeExecutableRelativePath: String = "node/bin/node",
        backendBundleRelativePath: String = "backend/sub-store.bundle.js"
    ) {
        self.version = version
        self.nodeExecutableRelativePath = nodeExecutableRelativePath
        self.backendBundleRelativePath = backendBundleRelativePath
    }

    enum CodingKeys: String, CodingKey {
        case version
        case nodeExecutableRelativePath
        case backendBundleRelativePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SubStoreResourceManifest()
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? defaults.version
        self.nodeExecutableRelativePath = try container.decodeIfPresent(String.self, forKey: .nodeExecutableRelativePath) ?? defaults.nodeExecutableRelativePath
        self.backendBundleRelativePath = try container.decodeIfPresent(String.self, forKey: .backendBundleRelativePath) ?? defaults.backendBundleRelativePath
    }
}

public struct SubStoreRuntimeStatus: Codable, Equatable, Sendable {
    public var configuration: SubStoreStatus
    public var isBackendRunning: Bool
    public var backendPID: Int32?
    public var backendURL: URL?
    public var resourceVersion: String?
    public var resourcesInstalled: Bool

    public init(
        configuration: SubStoreStatus = SubStoreStatus(),
        isBackendRunning: Bool = false,
        backendPID: Int32? = nil,
        backendURL: URL? = nil,
        resourceVersion: String? = nil,
        resourcesInstalled: Bool = false
    ) {
        self.configuration = configuration
        self.isBackendRunning = isBackendRunning
        self.backendPID = backendPID
        self.backendURL = backendURL
        self.resourceVersion = resourceVersion
        self.resourcesInstalled = resourcesInstalled
    }
}

public struct SubStoreEntry: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var displayName: String?
    public var icon: String?
    public var tags: [String]
    public var kind: SubStoreEntryKind

    public var id: String {
        "\(kind.rawValue):\(name)"
    }

    public init(
        name: String,
        displayName: String? = nil,
        icon: String? = nil,
        tags: [String] = [],
        kind: SubStoreEntryKind
    ) {
        self.name = name
        self.displayName = displayName
        self.icon = icon
        self.tags = tags
        self.kind = kind
    }

    /// Relative URL the Sub-Store backend serves for this entry. Sparkle uses
    /// the same `/download/...` path shape, with collections living under
    /// `/download/collection/...`.
    public var downloadPath: String {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        switch kind {
        case .subscription:
            return "/download/\(encodedName)"
        case .collection:
            return "/download/collection/\(encodedName)"
        }
    }

    public var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return name
    }
}

public enum SubStoreEntryKind: String, Codable, Sendable {
    case subscription
    case collection
}

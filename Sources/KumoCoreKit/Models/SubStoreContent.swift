import Foundation

// MARK: - Subscription

public struct SubStoreSubscription: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var displayName: String?
    public var icon: String?
    public var source: String?
    public var url: String?
    public var content: String?
    public var ua: String?
    public var proxy: String?
    public var tag: [String]?
    public var mergeSources: String?
    public var subUserinfo: String?
    public var ignoreFailedRemoteSub: String?
    public var headers: [String: String]?
    public var process: [JSONValue]?

    public var id: String { name }

    public init(
        name: String,
        displayName: String? = nil,
        icon: String? = nil,
        source: String? = nil,
        url: String? = nil,
        content: String? = nil,
        ua: String? = nil,
        proxy: String? = nil,
        tag: [String]? = nil,
        mergeSources: String? = nil,
        subUserinfo: String? = nil,
        ignoreFailedRemoteSub: String? = nil,
        headers: [String: String]? = nil,
        process: [JSONValue]? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.icon = icon
        self.source = source
        self.url = url
        self.content = content
        self.ua = ua
        self.proxy = proxy
        self.tag = tag
        self.mergeSources = mergeSources
        self.subUserinfo = subUserinfo
        self.ignoreFailedRemoteSub = ignoreFailedRemoteSub
        self.headers = headers
        self.process = process
    }

    public var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return name
    }

    public var isLocal: Bool {
        source == "local"
    }

    public var urlList: [String] {
        guard let url, !url.isEmpty else { return [] }
        return url.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Sub-Store backend serves single subscriptions at `/download/<name>`.
    public var downloadPath: String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "/download/\(encoded)"
    }
}

// MARK: - Collection

public struct SubStoreCollection: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var displayName: String?
    public var icon: String?
    public var subscriptions: [String]
    public var subscriptionTags: [String]?
    public var ignoreFailedRemoteSub: String?
    public var process: [JSONValue]?

    public var id: String { name }

    public init(
        name: String,
        displayName: String? = nil,
        icon: String? = nil,
        subscriptions: [String] = [],
        subscriptionTags: [String]? = nil,
        ignoreFailedRemoteSub: String? = nil,
        process: [JSONValue]? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.icon = icon
        self.subscriptions = subscriptions
        self.subscriptionTags = subscriptionTags
        self.ignoreFailedRemoteSub = ignoreFailedRemoteSub
        self.process = process
    }

    public var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return name
    }

    /// Sub-Store backend serves collections at `/download/collection/<name>`.
    public var downloadPath: String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "/download/collection/\(encoded)"
    }
}

// MARK: - Flow info

public struct SubStoreFlow: Codable, Equatable, Sendable {
    public var upload: Int64
    public var download: Int64
    public var total: Int64
    public var expires: Int64?
    public var remainingDays: Int?

    public init(
        upload: Int64 = 0,
        download: Int64 = 0,
        total: Int64 = 0,
        expires: Int64? = nil,
        remainingDays: Int? = nil
    ) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expires = expires
        self.remainingDays = remainingDays
    }

    public var used: Int64 { upload + download }

    public var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(used) / Double(total)))
    }

    public var expiryDate: Date? {
        guard let expires, expires > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expires))
    }

    enum CodingKeys: String, CodingKey {
        case upload
        case download
        case total
        case expires
        case expire
        case remainingDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.upload = (try? container.decode(Int64.self, forKey: .upload)) ?? 0
        self.download = (try? container.decode(Int64.self, forKey: .download)) ?? 0
        self.total = (try? container.decode(Int64.self, forKey: .total)) ?? 0
        if let expires = try? container.decode(Int64.self, forKey: .expires) {
            self.expires = expires
        } else if let expires = try? container.decode(Int64.self, forKey: .expire) {
            self.expires = expires
        } else {
            self.expires = nil
        }
        self.remainingDays = try? container.decode(Int.self, forKey: .remainingDays)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(upload, forKey: .upload)
        try container.encode(download, forKey: .download)
        try container.encode(total, forKey: .total)
        try container.encodeIfPresent(expires, forKey: .expires)
        try container.encodeIfPresent(remainingDays, forKey: .remainingDays)
    }
}

// MARK: - Preview

public struct SubStorePreviewResult: Codable, Equatable, Sendable {
    public var original: [JSONValue]
    public var processed: [JSONValue]

    public init(original: [JSONValue] = [], processed: [JSONValue] = []) {
        self.original = original
        self.processed = processed
    }
}

// MARK: - Files

public struct SubStoreFile: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var displayName: String?
    public var icon: String?
    public var type: String?
    public var source: String?
    public var url: String?
    public var content: String?
    public var ua: String?
    public var proxy: String?
    public var tag: [String]?
    public var mergeSources: String?
    public var ignoreFailedRemoteFile: String?
    public var process: [JSONValue]?

    public var id: String { name }

    public init(
        name: String,
        displayName: String? = nil,
        icon: String? = nil,
        type: String? = nil,
        source: String? = nil,
        url: String? = nil,
        content: String? = nil,
        ua: String? = nil,
        proxy: String? = nil,
        tag: [String]? = nil,
        mergeSources: String? = nil,
        ignoreFailedRemoteFile: String? = nil,
        process: [JSONValue]? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.icon = icon
        self.type = type
        self.source = source
        self.url = url
        self.content = content
        self.ua = ua
        self.proxy = proxy
        self.tag = tag
        self.mergeSources = mergeSources
        self.ignoreFailedRemoteFile = ignoreFailedRemoteFile
        self.process = process
    }

    public var resolvedDisplayName: String {
        displayName?.isEmpty == false ? (displayName ?? name) : name
    }
}

// MARK: - Modules

public struct SubStoreModule: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var content: String
    public var icon: String?
    public var description: String?

    public var id: String { name }

    public init(name: String, content: String = "", icon: String? = nil, description: String? = nil) {
        self.name = name
        self.content = content
        self.icon = icon
        self.description = description
    }
}

// MARK: - Artifacts

public struct SubStoreArtifact: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var displayName: String?
    public var type: String
    public var source: String
    public var platform: String?
    public var sync: Bool?
    public var url: String?
    public var updated: Int64?

    public var id: String { name }

    public init(
        name: String,
        displayName: String? = nil,
        type: String,
        source: String,
        platform: String? = nil,
        sync: Bool? = nil,
        url: String? = nil,
        updated: Int64? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.type = type
        self.source = source
        self.platform = platform
        self.sync = sync
        self.url = url
        self.updated = updated
    }

    public var resolvedDisplayName: String {
        displayName?.isEmpty == false ? (displayName ?? name) : name
    }
}

// MARK: - Tokens

public struct SubStoreShareToken: Identifiable, Codable, Equatable, Sendable {
    public var token: String
    public var type: String
    public var name: String
    public var exp: Int64?

    public var id: String { token }

    public init(token: String, type: String, name: String, exp: Int64? = nil) {
        self.token = token
        self.type = type
        self.name = name
        self.exp = exp
    }
}

// MARK: - Archives

public struct SubStoreArchive: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var type: String
    public var content: JSONValue?
    public var time: Int64?

    public var id: String { "\(type):\(name):\(time ?? 0)" }

    public init(name: String, type: String, content: JSONValue? = nil, time: Int64? = nil) {
        self.name = name
        self.type = type
        self.content = content
        self.time = time
    }
}

// MARK: - Settings

public struct SubStoreSettings: Codable, Equatable, Sendable {
    public var raw: [String: JSONValue]

    public init(raw: [String: JSONValue] = [:]) {
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.raw = (try? container.decode([String: JSONValue].self)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public subscript(key: String) -> JSONValue? {
        get { raw[key] }
        set { raw[key] = newValue }
    }
}

// MARK: - Logs

public struct SubStoreLogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var level: String?
    public var message: String
    public var time: Int64?

    public init(id: String = UUID().uuidString, level: String? = nil, message: String, time: Int64? = nil) {
        self.id = id
        self.level = level
        self.message = message
        self.time = time
    }
}

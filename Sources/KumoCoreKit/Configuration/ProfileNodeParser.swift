import Foundation
import Yams

/// Information about a single outbound node parsed from a Mihomo profile
/// YAML's `proxies:` array. Only the fields needed for downstream GeoIP
/// lookup are captured — everything else (cipher, password, transport, etc.)
/// stays inside the runtime YAML.
public struct ProfileNodeInfo: Equatable, Sendable {
    public let name: String
    public let server: String
    public let port: Int?

    public init(name: String, server: String, port: Int? = nil) {
        self.name = name
        self.server = server
        self.port = port
    }
}

/// Parses Mihomo profile YAML to extract outbound node metadata.
///
/// Mihomo's controller API intentionally does not expose `server` / `port` of
/// proxy nodes (security design), so any feature that wants the upstream
/// hostname must read the raw profile YAML. This parser is intentionally
/// permissive: invalid entries (missing `name` or `server`, wrong types) are
/// skipped silently so a partially-corrupt YAML still yields whatever nodes
/// it can.
public enum ProfileNodeParser {
    /// Parses the given YAML string and returns a mapping from proxy node
    /// `name` to `ProfileNodeInfo`. Group entries under `proxy-groups:` are
    /// ignored; only top-level `proxies:` entries are returned.
    ///
    /// - Returns: Empty dictionary when YAML is empty, has no `proxies:`
    ///   array, or no entries pass validation. Throws only if YAML itself
    ///   fails to parse.
    public static func parseNodes(yaml: String) throws -> [String: ProfileNodeInfo] {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [:]
        }

        let root = try Yams.load(yaml: yaml)
        guard let dict = root as? [String: Any] else {
            return [:]
        }

        guard let proxies = dict["proxies"] as? [Any] else {
            return [:]
        }

        var result: [String: ProfileNodeInfo] = [:]
        for entry in proxies {
            guard let proxy = entry as? [String: Any] else { continue }
            guard let name = string(from: proxy["name"]) else { continue }
            guard let server = string(from: proxy["server"]) else { continue }
            let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedServer.isEmpty else { continue }

            let port = portValue(from: proxy["port"])
            result[name] = ProfileNodeInfo(name: name, server: trimmedServer, port: port)
        }
        return result
    }

    /// Parses the given YAML string and returns the `proxy-groups:` array as
    /// a list of `ProxyGroup` placeholders suitable for rendering before the
    /// core is running. Each contained `ProxyNode` carries only the name
    /// listed in YAML — `type`, `delay`, `detectedCountry`, and
    /// `selectedProxyName` are all `nil` because that information only
    /// becomes available once mihomo serves `/proxies`.
    ///
    /// The result is sorted by `name.localizedCaseInsensitiveCompare` to
    /// match the order `MihomoControllerClient.proxyGroups()` uses, so the
    /// sidebar does not reshuffle when the core transitions from stopped to
    /// running.
    ///
    /// - Returns: Empty array when YAML is empty, missing `proxy-groups:`,
    ///   or all entries fail validation. Throws only if YAML itself fails to
    ///   parse.
    public static func parseProxyGroups(yaml: String) throws -> [ProxyGroup] {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let root = try Yams.load(yaml: yaml)
        guard let dict = root as? [String: Any] else {
            return []
        }
        guard let groups = dict["proxy-groups"] as? [Any] else {
            return []
        }

        var result: [ProxyGroup] = []
        for entry in groups {
            guard let group = entry as? [String: Any] else { continue }
            guard let rawName = string(from: group["name"]) else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let proxyList = group["proxies"] as? [Any] ?? []
            let nodes: [ProxyNode] = proxyList.compactMap { value in
                guard let raw = string(from: value) else { return nil }
                let proxyName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !proxyName.isEmpty else { return nil }
                return ProxyNode(name: proxyName)
            }

            // Drop groups with no usable proxies — they can't be rendered as
            // anything other than an empty section and the user can't tap
            // anything in them while the core is stopped anyway.
            guard !nodes.isEmpty else { continue }

            result.append(ProxyGroup(
                name: name,
                selectedProxyName: nil,
                proxies: nodes,
                testURL: nil
            ))
        }

        return result.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func string(from value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? CustomStringConvertible {
            return String(describing: value)
        }
        return nil
    }

    private static func portValue(from value: Any?) -> Int? {
        if let port = value as? Int { return port }
        if let port = value as? Int64 { return Int(port) }
        if let port = value as? UInt { return Int(port) }
        if let port = value as? String { return Int(port) }
        return nil
    }
}

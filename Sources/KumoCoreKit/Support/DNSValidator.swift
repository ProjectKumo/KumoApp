import Foundation

public enum DNSValidator {
    public static func isValidDomainWildcard(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Allow wildcards like *, +, +.example.com, *.example.com
        let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_*+")
        return trimmed.unicodeScalars.allSatisfy { allowedChars.contains($0) }
    }

    public static func isValidCIDR(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // IPv4 CIDR: 1.2.3.4/24 or 1.2.3.4
        // IPv6 CIDR: fc00::/18 or fc00::
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let prefix = Int(parts[1]),
                  prefix >= 0, prefix <= 128 else {
                return false
            }
            let ip = String(parts[0])
            return isValidIPv4(ip) || isValidIPv6(ip)
        }

        return isValidIPv4(trimmed) || isValidIPv6(trimmed)
    }

    public static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy {
            guard let num = Int($0), num >= 0, num <= 255 else { return false }
            return String($0) == String(num) // no leading zeros
        }
    }

    public static func isValidIPv6(_ value: String) -> Bool {
        // Simplified IPv6 validation
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 8 else { return false }
        for part in parts {
            if part.isEmpty { continue }
            guard part.count <= 4,
                  UInt16(part, radix: 16) != nil else { return false }
        }
        return trimmed.contains(":")
    }

    public static func isValidListenAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true } // empty means default

        // Accept formats like ":53", "0.0.0.0:53", "127.0.0.1:53", "[::]:53"
        if trimmed.hasPrefix("[") {
            // IPv6 with brackets: [::]:53
            guard let bracketEnd = trimmed.lastIndex(of: "]") else { return false }
            let afterBracket = trimmed.index(after: bracketEnd)
            let portPart = String(trimmed[afterBracket...])
            guard portPart.hasPrefix(":") else { return false }
            let portStr = String(portPart.dropFirst())
            guard let port = Int(portStr), port > 0, port <= 65535 else { return false }
            let ipPart = String(trimmed[trimmed.index(after: trimmed.startIndex)..<bracketEnd])
            return isValidIPv6(ipPart)
        }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 2 {
                let host = String(parts[0])
                let portStr = String(parts[1])
                guard let port = Int(portStr), port > 0, port <= 65535 else { return false }
                return host.isEmpty || isValidIPv4(host) || host == "localhost"
            }
            // Could be IPv6 without brackets — not standard for listen addresses
            return false
        }

        // Just a port number is not valid; must have colon format
        return false
    }

    public static func isValidFakeIPFilterMode(_ value: String) -> Bool {
        value.isEmpty || ["blacklist", "whitelist"].contains(value)
    }

    public static func isValidCacheAlgorithm(_ value: String) -> Bool {
        value.isEmpty || ["lru", "arc"].contains(value)
    }
}

public enum SnifferValidator {
    public static func parsePortString(_ value: String) -> [Int] {
        value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { Int($0) }
    }

    public static func isValidPortList(_ ports: [Int]) -> Bool {
        ports.allSatisfy { $0 > 0 && $0 <= 65535 }
    }
}

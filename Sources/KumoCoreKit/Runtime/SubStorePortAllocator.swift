import Foundation
import Darwin

public enum SubStorePortAllocator {
    public static func availablePort(startingAt preferredPort: Int, allowLAN: Bool) async throws -> Int {
        for port in preferredPort...65535 {
            if canBind(port: port, allowLAN: allowLAN) {
                return port
            }
        }
        throw KumoError.commandFailed("No available Sub-Store port found from \(preferredPort).")
    }

    private static func canBind(port: Int, allowLAN: Bool) -> Bool {
        guard port > 0, port <= 65535 else {
            return false
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: allowLAN ? INADDR_ANY.bigEndian : inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

final class SubStoreContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func consumeOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        return true
    }
}

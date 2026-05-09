import Foundation
import Network

/// Single-shot lock used to coordinate `withCheckedContinuation` across the
/// nonisolated callbacks fired by Network framework. Closures captured by
/// `NWListener.stateUpdateHandler` and `NWConnection.stateUpdateHandler`
/// cannot mutate a captured `var` under Swift 6 strict concurrency, so we
/// promote the "did already resume?" flag into a reference type.
private final class ContinuationGuard: @unchecked Sendable {
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

/// Minimal local HTTP server that serves a single PAC script payload to any
/// inbound request. Designed for system-proxy "auto" mode: macOS dispatches
/// PAC requests via `networksetup -setautoproxyurl http://127.0.0.1:<port>/proxy.pac`,
/// so we only need to respond with `application/x-ns-proxy-autoconfig` content.
///
/// The server binds to `127.0.0.1` on an OS-assigned port. The chosen port is
/// returned from `start` so callers can wire it into `networksetup`.
public actor PACServer {
    private var listener: NWListener?
    private var script: String = ""
    private var boundPort: UInt16?

    public init() {}

    public var isRunning: Bool {
        listener != nil
    }

    public var currentPort: UInt16? {
        boundPort
    }

    /// Start (or hot-swap script of) the PAC server. Returns the bound port.
    @discardableResult
    public func start(script: String) async throws -> UInt16 {
        self.script = script

        if let listener, let boundPort, listener.state == .ready {
            return boundPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw KumoError.commandFailed("PAC server bind failed: \(error.localizedDescription)")
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handle(connection: connection)
            }
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let guardFlag = ContinuationGuard()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue, guardFlag.consumeOnce() {
                        continuation.resume(returning: port)
                    }
                case .failed(let error):
                    if guardFlag.consumeOnce() {
                        continuation.resume(throwing: KumoError.commandFailed("PAC listener failed: \(error.localizedDescription)"))
                    }
                case .cancelled:
                    if guardFlag.consumeOnce() {
                        continuation.resume(throwing: KumoError.commandFailed("PAC listener cancelled before becoming ready."))
                    }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .utility))
        }

        self.listener = listener
        self.boundPort = port
        return port
    }

    /// Replace the script served by an already-running PAC server. No-op if
    /// the server is not running.
    public func updateScript(_ script: String) {
        self.script = script
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        boundPort = nil
        script = ""
    }

    private func handle(connection: NWConnection) async {
        let body = script
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = Data(response.utf8)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let guardFlag = ContinuationGuard()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guardFlag.consumeOnce() {
                        connection.send(content: data, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                        continuation.resume()
                    }
                case .failed, .cancelled:
                    if guardFlag.consumeOnce() {
                        connection.cancel()
                        continuation.resume()
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }
}

import ArgumentParser
import Foundation
import KumoCoreKit

public final class CLIRuntime: @unchecked Sendable {
    nonisolated(unsafe) private static var storage: CLIRuntime?
    nonisolated(unsafe) public static var current: CLIRuntime {
        get {
            guard let storage else {
                fatalError("CLIRuntime.current was accessed before initialization.")
            }
            return storage
        }
        set {
            storage = newValue
        }
    }

    let controller: KumoController
    let options: RuntimeOptions
    let renderer: OutputRenderer
    let debugLogStore: DebugLogStore
    private var timing: [(String, Int)] = []
    private let startedAt = Date()

    init(options: RuntimeOptions, controller: KumoController = KumoController()) {
        self.options = options
        self.controller = controller
        self.renderer = OutputRenderer(options: options)
        self.debugLogStore = DebugLogStore(paths: controller.paths, options: options)
        Self.current = self
    }

    func write<T: Encodable>(_ value: T, text: (T) -> String) {
        guard !options.isSilent || options.wantsJSON else { return }
        if options.wantsJSON {
            writeJSON(CLIResponse(ok: true, data: value))
        } else {
            renderer.stdout(text(value))
        }
    }

    func writeText(_ text: String) {
        guard !options.isSilent else { return }
        renderer.stdout(text)
    }

    func writeError(_ error: Error) {
        let message = Self.message(for: error)
        if options.wantsJSON {
            writeJSON(CLIResponse<String>(ok: false, error: message))
            return
        }
        renderer.stderr(renderer.error("[error] \(message)"))
        if let suggestion = helpSuggestion(for: error) {
            renderer.stderr(renderer.dim(suggestion))
        }
        if let path = debugLogStore.currentLogPath, options.logsMax != 0 {
            renderer.stderr("A complete log of this run can be found in:\n    \(path)")
        }
    }

    func log(_ level: LogLevel, _ message: String) {
        debugLogStore.append(level: level, message: message)
        guard options.logLevel.allows(level), !options.wantsJSON, !options.isSilent else { return }
        renderer.stderr("\(level.rawValue) \(LogRedactor.redact(message))")
    }

    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let start = DispatchTime.now()
        let value = try operation()
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        timing.append((name, elapsed))
        return value
    }

    func finish(success: Bool) throws {
        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        debugLogStore.writeSummary(success: success, durationMilliseconds: duration)
        if options.timing {
            let path = try debugLogStore.writeTiming(timing, totalMilliseconds: duration)
            if !options.wantsJSON, !options.isSilent {
                for entry in timing {
                    renderer.stderr("timing \(entry.0) \(entry.1)ms")
                }
                renderer.stderr("timing total \(duration)ms")
                renderer.stderr("Timing info written to:\n    \(path.path)")
            }
        }
    }

    private func writeJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        renderer.stdout(string)
    }

    private static func message(for error: Error) -> String {
        if let validation = error as? ValidationError {
            return validation.message
        }
        let argumentParserMessage = KumoCommand.message(for: error)
        if !argumentParserMessage.isEmpty {
            return argumentParserMessage
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func helpSuggestion(for error: Error) -> String? {
        guard error is ValidationError else { return nil }
        return "Run \"kumo --help\" for more info."
    }
}

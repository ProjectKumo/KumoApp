import Foundation
import KumoCoreKit

struct DebugLogStore {
    let directory: URL
    let options: RuntimeOptions
    let currentLogPath: String?
    private let fileManager = FileManager.default

    init(paths: KumoPaths, options: RuntimeOptions) {
        self.options = options
        if let logsDir = options.logsDir {
            self.directory = URL(fileURLWithPath: logsDir, isDirectory: true)
        } else {
            self.directory = paths.logsDirectory.appendingPathComponent("cli", isDirectory: true)
        }
        if options.logsMax == 0 {
            self.currentLogPath = nil
        } else {
            self.currentLogPath = directory.appendingPathComponent("\(Self.timestamp())-kumo-debug-0.log").path
        }
    }

    func append(level: LogLevel, message: String) {
        guard let currentLogPath else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = "\(Date()) \(level.rawValue) \(LogRedactor.redact(message))\n"
        if let data = line.data(using: .utf8) {
            if fileManager.fileExists(atPath: currentLogPath),
               let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: currentLogPath)) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: currentLogPath))
            }
        }
    }

    func writeSummary(success: Bool, durationMilliseconds: Int) {
        append(level: success ? .notice : .error, message: "kumo exit=\(success ? 0 : 1) duration=\(durationMilliseconds)ms")
        try? rotate()
    }

    func writeTiming(_ entries: [(String, Int)], totalMilliseconds: Int) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(Self.timestamp())-kumo-timing.json")
        let payload = TimingPayload(
            timers: Dictionary(uniqueKeysWithValues: entries.map { ($0.0, $0.1) }),
            totalMilliseconds: totalMilliseconds
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: url)
        return url
    }

    func recentEntries(limit: Int, minimumLevel: LogLevel?) -> [CLILogEntry] {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.contains("kumo-debug") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
            .map { url in
                let summary = (try? String(contentsOf: url, encoding: .utf8).split(separator: "\n").last.map(String.init)) ?? url.lastPathComponent
                let level = LogLevel.allCases.first { summary.contains(" \($0.rawValue) ") } ?? .notice
                return CLILogEntry(createdAt: url.lastPathComponent, level: level, summary: summary)
            }
            .filter { entry in
                guard let minimumLevel else { return true }
                return minimumLevel.allows(entry.level)
            }
    }

    func clean(dryRun: Bool) throws -> CLILogCleanReport {
        let files = ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.contains("kumo-debug") || $0.lastPathComponent.contains("kumo-timing") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        let remove = Array(files.dropFirst(max(options.logsMax, 0)))
        if !dryRun {
            for file in remove {
                try? fileManager.removeItem(at: file)
            }
        }
        return CLILogCleanReport(dryRun: dryRun, matchedFiles: files.count, wouldRemoveFiles: remove.count)
    }

    private func rotate() throws {
        _ = try clean(dryRun: false)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }
}

enum LogRedactor {
    static func redact(_ value: String) -> String {
        var output = value
        let patterns = [
            "(?i)(authorization:\\s*bearer\\s+)[^\\s]+",
            "(?i)(secret=)[^\\s&]+",
            "(?i)(token=)[^\\s&]+",
            "(https?://[^:/\\s]+:)[^@\\s]+@"
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "$1[redacted]", options: .regularExpression)
        }
        return output
    }
}

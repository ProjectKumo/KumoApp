import Foundation

public struct CoreStateStore: Sendable {
    private let stateFile: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: KumoPaths = KumoPaths()) {
        self.stateFile = paths.stateFile
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> CoreStatus {
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return CoreStatus()
        }

        let data = try Data(contentsOf: stateFile)
        return try decoder.decode(CoreStatus.self, from: data)
    }

    public func save(_ status: CoreStatus) throws {
        try FileManager.default.createDirectory(
            at: stateFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(status)
        try data.write(to: stateFile, options: .atomic)
    }
}

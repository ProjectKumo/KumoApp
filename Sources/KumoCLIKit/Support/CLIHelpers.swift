import Foundation

func installManagedCoreIfNeeded() async throws {
    let controller = CLIRuntime.current.controller
    let status = try controller.status()
    let candidates = try controller.coreCandidates()
    let managedCorePath = controller.paths.managedCoreExecutable.path
    let managedCoreInstalled = FileManager.default.isExecutableFile(atPath: managedCorePath)
    let shouldInstall = if status.corePath == nil {
        !managedCoreInstalled
    } else {
        candidates.isEmpty
    }

    guard shouldInstall else { return }
    _ = try await controller.installManagedCore()
}

func currentDirectoryURL() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

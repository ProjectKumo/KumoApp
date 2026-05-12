import Foundation
import Observation
import KumoCoreKit

/// State container for the Sub-Store feature. Keeps Sub-Store-specific
/// content (subscriptions, collections, files, modules, artifacts, archives,
/// tokens, settings, logs) out of `KumoAppStore` so the rest of the app does
/// not invalidate when Sub-Store state changes.
@MainActor
@Observable
final class SubStoreStore {
    enum Section: String, CaseIterable, Identifiable {
        case subscriptions
        case collections
        case files
        case modules
        case artifacts
        case archives
        case tokens
        case settings
        case logs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .subscriptions: "Subscriptions"
            case .collections: "Collections"
            case .files: "Files"
            case .modules: "Modules"
            case .artifacts: "Artifacts"
            case .archives: "Archives"
            case .tokens: "Tokens"
            case .settings: "Settings"
            case .logs: "Logs"
            }
        }

        var symbol: String {
            switch self {
            case .subscriptions: "rectangle.stack"
            case .collections: "square.stack.3d.up"
            case .files: "doc.text"
            case .modules: "curlybraces"
            case .artifacts: "shippingbox"
            case .archives: "archivebox"
            case .tokens: "key"
            case .settings: "gearshape"
            case .logs: "doc.text.magnifyingglass"
            }
        }
    }

    enum Selection: Hashable {
        case subscription(String)
        case collection(String)
        case file(String)
        case module(String)
        case artifact(String)
        case archive(String)
        case token(String)
    }

    var section: Section = .subscriptions
    var selection: Selection?

    var subscriptions: [SubStoreSubscription] = []
    var collections: [SubStoreCollection] = []
    var files: [SubStoreFile] = []
    var modules: [SubStoreModule] = []
    var artifacts: [SubStoreArtifact] = []
    var archives: [SubStoreArchive] = []
    var tokens: [SubStoreShareToken] = []
    var settings: SubStoreSettings = SubStoreSettings()
    var logs: [SubStoreLogEntry] = []

    var flowByName: [String: SubStoreFlow] = [:]
    var previewBySubscription: [String: SubStorePreviewResult] = [:]
    var previewByCollection: [String: SubStorePreviewResult] = [:]

    var isLoading = false
    var isFetchingFlow: Set<String> = []
    var isPreviewing: Set<String> = []
    var errorMessage: String?

    private let controller: KumoController

    init(controller: KumoController) {
        self.controller = controller
    }

    // MARK: - Bootstrap

    func loadInitial() async {
        await refreshSubscriptions()
        await refreshCollections()
    }

    func client() throws -> SubStoreClient {
        try controller.subStoreClient()
    }

    var isBackendAvailable: Bool {
        (try? controller.subStoreClient()) != nil
    }

    // MARK: - Section refresh

    func refreshActiveSection() async {
        switch section {
        case .subscriptions: await refreshSubscriptions()
        case .collections: await refreshCollections()
        case .files: await refreshFiles()
        case .modules: await refreshModules()
        case .artifacts: await refreshArtifacts()
        case .archives: await refreshArchives()
        case .tokens: await refreshTokens()
        case .settings: await refreshSettings()
        case .logs: await refreshLogs()
        }
    }

    func refreshSubscriptions() async {
        await perform {
            self.subscriptions = try await self.client().subscriptions()
        }
    }

    func refreshCollections() async {
        await perform {
            self.collections = try await self.client().collections()
        }
    }

    func refreshFiles() async {
        await perform {
            self.files = try await self.client().files()
        }
    }

    func refreshModules() async {
        await perform {
            self.modules = try await self.client().modules()
        }
    }

    func refreshArtifacts() async {
        await perform {
            self.artifacts = try await self.client().artifacts()
        }
    }

    func refreshArchives() async {
        await perform {
            self.archives = try await self.client().archives()
        }
    }

    func refreshTokens() async {
        await perform {
            self.tokens = try await self.client().tokens()
        }
    }

    func refreshSettings() async {
        await perform {
            self.settings = try await self.client().settings()
        }
    }

    func refreshLogs(limit: Int = 200) async {
        await perform {
            self.logs = try await self.client().logs(limit: limit)
        }
    }

    // MARK: - Subscriptions

    func loadFlow(for name: String) async {
        guard !isFetchingFlow.contains(name) else { return }
        isFetchingFlow.insert(name)
        defer { isFetchingFlow.remove(name) }
        do {
            flowByName[name] = try await client().subscriptionFlow(name: name)
        } catch {
            // Sub-Store backend returns 404 / structured failure when no flow
            // info is available; simply drop the cached value.
            flowByName[name] = nil
        }
    }

    func deleteSubscription(name: String, archive: Bool) async {
        await perform {
            try await self.client().deleteSubscription(name: name, archive: archive)
            await self.refreshSubscriptions()
            if case .subscription(let active) = self.selection, active == name {
                self.selection = nil
            }
        }
    }

    func saveSubscription(name: String?, draft: SubStoreSubscription) async -> Bool {
        var success = false
        await perform {
            if let name {
                _ = try await self.client().updateSubscription(name: name, draft)
            } else {
                _ = try await self.client().createSubscription(draft)
            }
            await self.refreshSubscriptions()
            success = true
        }
        return success
    }

    func reorderSubscriptions(_ list: [SubStoreSubscription]) async {
        await perform {
            try await self.client().replaceSubscriptions(list)
            self.subscriptions = list
        }
    }

    func previewSubscription(_ subscription: SubStoreSubscription, target: String = "JSON") async {
        guard !isPreviewing.contains(subscription.name) else { return }
        isPreviewing.insert(subscription.name)
        defer { isPreviewing.remove(subscription.name) }
        do {
            previewBySubscription[subscription.name] = try await client().previewSubscription(subscription, target: target)
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Collections

    func deleteCollection(name: String, archive: Bool) async {
        await perform {
            try await self.client().deleteCollection(name: name, archive: archive)
            await self.refreshCollections()
            if case .collection(let active) = self.selection, active == name {
                self.selection = nil
            }
        }
    }

    func saveCollection(name: String?, draft: SubStoreCollection) async -> Bool {
        var success = false
        await perform {
            if let name {
                _ = try await self.client().updateCollection(name: name, draft)
            } else {
                _ = try await self.client().createCollection(draft)
            }
            await self.refreshCollections()
            success = true
        }
        return success
    }

    func reorderCollections(_ list: [SubStoreCollection]) async {
        await perform {
            try await self.client().replaceCollections(list)
            self.collections = list
        }
    }

    func previewCollection(_ collection: SubStoreCollection, target: String = "JSON") async {
        guard !isPreviewing.contains(collection.name) else { return }
        isPreviewing.insert(collection.name)
        defer { isPreviewing.remove(collection.name) }
        do {
            previewByCollection[collection.name] = try await client().previewCollection(collection, target: target)
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Files

    func saveFile(name: String?, draft: SubStoreFile) async -> Bool {
        var success = false
        await perform {
            if let name {
                _ = try await self.client().updateFile(name: name, draft)
            } else {
                _ = try await self.client().createFile(draft)
            }
            await self.refreshFiles()
            success = true
        }
        return success
    }

    func deleteFile(name: String) async {
        await perform {
            try await self.client().deleteFile(name: name)
            await self.refreshFiles()
            if case .file(let active) = self.selection, active == name {
                self.selection = nil
            }
        }
    }

    // MARK: - Modules

    func saveModule(name: String, content: String) async -> Bool {
        var success = false
        await perform {
            try await self.client().updateModule(name: name, content: content)
            await self.refreshModules()
            success = true
        }
        return success
    }

    func deleteModule(name: String) async {
        await perform {
            try await self.client().deleteModule(name: name)
            await self.refreshModules()
            if case .module(let active) = self.selection, active == name {
                self.selection = nil
            }
        }
    }

    // MARK: - Artifacts

    func saveArtifact(name: String?, draft: SubStoreArtifact) async -> Bool {
        var success = false
        await perform {
            if let name {
                _ = try await self.client().updateArtifact(name: name, draft)
            } else {
                _ = try await self.client().createArtifact(draft)
            }
            await self.refreshArtifacts()
            success = true
        }
        return success
    }

    func deleteArtifact(name: String) async {
        await perform {
            try await self.client().deleteArtifact(name: name)
            await self.refreshArtifacts()
            if case .artifact(let active) = self.selection, active == name {
                self.selection = nil
            }
        }
    }

    func syncAllArtifacts() async {
        await perform {
            try await self.client().syncArtifacts()
            await self.refreshArtifacts()
        }
    }

    func syncArtifact(name: String) async {
        await perform {
            try await self.client().syncArtifact(name: name)
            await self.refreshArtifacts()
        }
    }

    // MARK: - Tokens

    func createToken(type: String, name: String, expiresAt: Int64?) async {
        await perform {
            _ = try await self.client().createToken(type: type, name: name, expiresAt: expiresAt)
            await self.refreshTokens()
        }
    }

    func deleteToken(token: String) async {
        await perform {
            try await self.client().deleteToken(token: token)
            await self.refreshTokens()
        }
    }

    // MARK: - Archives

    func deleteArchive(_ archive: SubStoreArchive) async {
        guard let time = archive.time else { return }
        await perform {
            try await self.client().deleteArchive(type: archive.type, name: archive.name, time: time)
            await self.refreshArchives()
        }
    }

    func restoreArchive(_ archive: SubStoreArchive) async {
        guard let time = archive.time else { return }
        await perform {
            try await self.client().restoreArchive(type: archive.type, name: archive.name, time: time)
            await self.refreshArchives()
        }
    }

    // MARK: - Settings

    func saveSettings(_ updated: SubStoreSettings) async {
        await perform {
            self.settings = try await self.client().updateSettings(updated)
        }
    }

    func performGistBackup(action: String) async {
        await perform {
            try await self.client().gistBackupAction(action)
        }
    }

    // MARK: - Helpers

    func clearError() {
        errorMessage = nil
    }

    private func perform(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

import AppIntents
import Foundation
import KumoCoreKit

/// AppIntents metadata extractor cannot see enum cases declared in another
/// SPM module, so we redeclare `OutboundMode` locally as `KumoModeChoice`
/// and bridge to/from `KumoCoreKit.OutboundMode` when running an intent.
enum KumoModeChoice: String, AppEnum {
    case rule
    case global
    case direct

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Outbound Mode"
    static let caseDisplayRepresentations: [KumoModeChoice: DisplayRepresentation] = [
        .rule: DisplayRepresentation(title: "Rule"),
        .global: DisplayRepresentation(title: "Global"),
        .direct: DisplayRepresentation(title: "Direct")
    ]

    var coreMode: OutboundMode {
        switch self {
        case .rule: .rule
        case .global: .global
        case .direct: .direct
        }
    }
}

/// Helper that resolves the live `KumoAppStore` shared by all intents. We
/// prefer touching the store rather than constructing a fresh
/// `KumoController` so that intent results stay in sync with the SwiftUI UI.
private enum IntentResolver {
    @MainActor
    static func store() throws -> KumoAppStore {
        guard let store = KumoAppContext.shared.store else {
            throw KumoIntentError.appNotReady
        }
        return store
    }
}

enum KumoIntentError: LocalizedError {
    case appNotReady

    var errorDescription: String? {
        switch self {
        case .appNotReady:
            return "Kumo is launching; try again in a moment."
        }
    }
}

struct StartKumoIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Kumo"
    static let description = IntentDescription("Start the Mihomo core managed by Kumo.")

    func perform() async throws -> some IntentResult {
        let store = try await MainActor.run { try IntentResolver.store() }
        await store.startCore()
        return .result()
    }
}

struct StopKumoIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Kumo"
    static let description = IntentDescription("Stop the running Mihomo core.")

    func perform() async throws -> some IntentResult {
        let store = try await MainActor.run { try IntentResolver.store() }
        await MainActor.run { store.stopCore() }
        return .result()
    }
}

struct SetKumoModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Kumo Mode"
    static let description = IntentDescription("Switch outbound rule between Rule, Global, and Direct.")

    @Parameter(title: "Mode")
    var mode: KumoModeChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try await MainActor.run { try IntentResolver.store() }
        let coreMode = mode.coreMode
        await store.setMode(coreMode)
        let displayName = coreMode.displayName
        return .result(dialog: IntentDialog("Switched Kumo mode to \(displayName)."))
    }
}

struct ToggleSystemProxyIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Kumo System Proxy"
    static let description = IntentDescription("Enable or disable macOS system proxy via Kumo.")

    @Parameter(title: "Enable")
    var enable: Bool

    func perform() async throws -> some IntentResult {
        let store = try await MainActor.run { try IntentResolver.store() }
        await MainActor.run { store.setSystemProxyEnabled(enable) }
        return .result()
    }
}

struct RefreshKumoIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Kumo"
    static let description = IntentDescription("Reload Kumo status, profiles, proxies, and inspect data.")

    func perform() async throws -> some IntentResult {
        let store = try await MainActor.run { try IntentResolver.store() }
        await store.refreshAll()
        return .result()
    }
}

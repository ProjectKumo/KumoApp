import AppIntents

/// Bundles Kumo's intents into Shortcuts / Spotlight phrases. The phrases
/// listed here become candidates surfaced by macOS Shortcuts, Siri, and the
/// Shortcuts launcher in the menu bar.
struct KumoShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartKumoIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Turn on \(.applicationName)"
            ],
            shortTitle: "Start Kumo",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: StopKumoIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Turn off \(.applicationName)"
            ],
            shortTitle: "Stop Kumo",
            systemImageName: "stop.fill"
        )

        AppShortcut(
            intent: RefreshKumoIntent(),
            phrases: [
                "Refresh \(.applicationName)"
            ],
            shortTitle: "Refresh Kumo",
            systemImageName: "arrow.clockwise"
        )

        AppShortcut(
            intent: SetKumoModeIntent(),
            phrases: [
                "Set \(.applicationName) mode"
            ],
            shortTitle: "Set Kumo Mode",
            systemImageName: "arrow.triangle.branch"
        )

        AppShortcut(
            intent: ToggleSystemProxyIntent(),
            phrases: [
                "Toggle \(.applicationName) system proxy"
            ],
            shortTitle: "Toggle System Proxy",
            systemImageName: "switch.2"
        )
    }
}

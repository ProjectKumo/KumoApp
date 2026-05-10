# macOS SwiftUI Interface

## Scope

`KumoApp` is the native macOS frontend. It owns windows, menus, Settings, the menu bar status item, App Intents, and SwiftUI state coordination. It does not own Mihomo lifecycle or profile generation; those responsibilities live in `KumoCoreKit`.

## App Scene Structure

The app uses:

- `WindowGroup(id: "main")` for the primary resizable Mac window.
- `Window("About Kumo", id: "about")` for the custom About window shared by the App menu and status item menu.
- `Settings` for preferences reachable through the standard app menu (General / Preferences / Updates tabs).
- `KumoStatusItemController` for the persistent menu bar icon and native quick menu. It uses `NSStatusItem` so Kumo can rebuild menu content dynamically and avoid SwiftUI `MenuBarExtra` visibility limitations.
- `CommandMenu("Control")` for keyboard-accessible Kumo commands.
- `CommandGroup(after: .toolbar)` to expose `Toggle Sidebar` (Cmd+Ctrl+S).
- `@NSApplicationDelegateAdaptor(KumoAppDelegate.self)` to bridge AppKit-only behaviour (status item setup, Services menu, Spotlight handoff, Dock badge timer, `SMAppService.mainApp` synchronisation, `applicationShouldTerminateAfterLastWindowClosed`).

`KumoAppContext.shared` is a tiny `@MainActor` singleton that exposes the live `KumoAppStore` and SwiftUI window-opening actions to the AppDelegate, status item, App Intents, and Services callbacks (none of which sit inside the SwiftUI view tree).

The main window keeps standard macOS chrome, a unified toolbar, and a sensible minimum size.

## View Structure

`ContentView` uses `NavigationSplitView` with a source-list sidebar grouped into three sections:

- Daily: `OverviewView`, `ProfilesView`, `ProxiesView`
- Inspect: `ConnectionsView`, `LogsView`, `RulesView`
- Configure: `CoreView`, `SystemProxyView`, `DNSView`, `TunView`, `SnifferView`, `ResourcesView`, `OverridesView`, `SubStoreView`

`KumoAppStore` is an `@Observable` object that bridges SwiftUI state to `KumoCoreKit`. Views should call store methods instead of directly constructing controller clients.

The toolbar mode switcher mirrors Sparkle's outbound mode behavior: changing
Rule / Global / Direct persists the controlled mode, patches Mihomo's running
`/configs` mode, closes existing connections, and refreshes proxy groups. This
uses a dedicated `isSwitchingMode` state instead of the global `isLoading` flag
so the Start / Stop toolbar action does not flash disabled during a mode-only
change.

The Overview metric cards are interactive summaries. They use native `Button`
controls to navigate into the relevant sidebar destinations and expose focused
context-menu actions such as refresh, proxy toggle, or opening the matching
settings page.

The Configure views may begin as small setting surfaces, but user-visible controls must correspond to shared `KumoCoreKit` behavior. Do not add a SwiftUI-only setting that bypasses the runtime builder, state store, or controller facade.

## Liquid Glass Usage

Liquid Glass is used sparingly:

- Status cards
- Interactive proxy chips
- Main grouped controls

The implementation provides fallback material backgrounds for older macOS versions. Interactive glass is only used on controls that perform actions.

`KumoGlassSurfaceModifier` always passes a `tint: Color` (default `.clear`) so SwiftUI can interpolate hover / selection tints across state changes without rebuilding the modifier chain.

## Settings Surface

`SettingsView` is a three-tab `TabView`, with About available as a separate window:

- **General** — read-only status (profile, mode, system proxy) plus a lightweight About shortcut.
- **Preferences** — `Open at Login` (driven by `SMAppService.mainApp`) and `Quit when last window closes` (read by `applicationShouldTerminateAfterLastWindowClosed`).
- **Updates** — channel picker, optional manifest URL override, and GitHub Releases update checks backed by `AppUpdateManager`.
- **About Kumo window** — app icon, version/build, author GitHub link, project links, and the same update-check state used by Settings.

Preferences persist to `~/Library/Application Support/Kumo/preferences.json` via `UserPreferencesStore`. See [Persistence and Logging](../operations/persistence-logging.md) for fields.

## Accessibility

All icon-only controls should have meaningful labels. The toolbar uses `Label` so VoiceOver and tooltips have clear names. The app should also preserve keyboard access for start, stop, refresh, mode switching, list navigation, filtering, and destructive confirmation.

`KumoUIComponents.swift` exposes `kumoSubtleBackground(in:)` and `kumoAdaptiveTextWeight(...)` helpers that read `colorSchemeContrast` and `legibilityWeight` from the environment so custom hairlines / pill backgrounds / non-standard font weights still respond to the user's Increase Contrast and Bold Text preferences.

## Design Constraints

- Avoid dense dashboards.
- Keep Inspect and Configure panels secondary to Daily workflow.
- Keep destination titles in the unified toolbar / navigation chrome; do not repeat the same title as a large in-page heading.
- Prefer system fonts, semantic colors, and standard controls.
- Preserve window resizing and standard traffic light buttons.
- Prefer native SwiftUI `Form`, `List`, `Table`, `Menu`, `Picker`, `Toggle`, `PasteButton`, and `fileImporter` before custom controls.

## System Integration Hooks

These integration points all rely on the `.app` bundle generated by `make app`, not on `swift run`:

- **Services menu** — `Info.plist` `NSServices` registers "Import Profile to Kumo"; `KumoAppDelegate.importProfileURL(_:userData:error:)` consumes the pasteboard string and calls `KumoAppStore.importRemoteProfile(...)`.
- **Spotlight** — `SpotlightIndexer` indexes profile summaries on launch and after profile mutations. Tapping a Spotlight result handoff calls `KumoAppContext.handleUserActivity(_:)` which selects the matching profile.
- **App Intents** — `KumoIntents.swift` exposes Start / Stop / Refresh / SetMode / ToggleSystemProxy intents, surfaced via `KumoShortcutsProvider`. `KumoModeChoice` is a local mirror of `OutboundMode` because AppIntents metadata extraction cannot see enums declared in another SPM module.
- **Dock badge** — A 1 s timer in the AppDelegate writes connection count into `NSApp.dockTile.badgeLabel`.

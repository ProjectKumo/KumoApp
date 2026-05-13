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
- `CommandMenu("Navigate")` for keyboard-accessible jumps to the primary Daily
  and Inspect destinations without moving navigation state into `KumoCoreKit`.
- `@NSApplicationDelegateAdaptor(KumoAppDelegate.self)` to bridge AppKit-only behaviour (status item setup, Services menu, Spotlight handoff, Dock badge timer, `SMAppService.mainApp` synchronisation, `applicationShouldTerminateAfterLastWindowClosed`).
- `UNUserNotificationCenter` integration for update notifications: update-available prompts, install progress stage updates, and actionable buttons routed back to `KumoAppStore`.

`KumoAppContext.shared` is a tiny `@MainActor` singleton that exposes the live `KumoAppStore` and SwiftUI window-opening actions to the AppDelegate, status item, App Intents, and Services callbacks (none of which sit inside the SwiftUI view tree).

The main window keeps standard macOS chrome, a unified toolbar, and a sensible minimum size.

## View Structure

`ContentView` uses `NavigationSplitView` with a source-list sidebar grouped into three sections:

- Daily: `OverviewView`, `ProfilesView`, `ProxiesView`
- Inspect: `ConnectionsView`, `LogsView`, `RulesView`
- Configure: `CoreView`, `SystemProxyView`, `DNSView`, `TunView`, `SnifferView`, `ResourcesView`, `OverridesView`, `SubStoreView`, `AgentSkillsView`

`KumoAppStore` is an `@Observable` object that bridges SwiftUI state to `KumoCoreKit`. Views should call store methods instead of directly constructing controller clients.

The toolbar mode switcher mirrors Sparkle's outbound mode behavior: changing
Rule / Global / Direct persists the controlled mode, patches Mihomo's running
`/configs` mode, closes existing connections, and refreshes proxy groups. This
uses a dedicated `isSwitchingMode` state instead of the global `isLoading` flag
so the Start / Stop toolbar action does not flash disabled during a mode-only
change.

Inspect pages keep toolbar search attached to the page container rather than
only to populated `Table` / `List` branches. A no-match state must not remove
the search field, because users need the same toolbar control to clear or edit
the query.
The Connections table shows process icons in the Process column when Mihomo
returns `metadata.processPath`. Icons are resolved with `NSWorkspace` from the
enclosing `.app` / `.xpc` bundle and cached in the SwiftUI view layer; the
shared `ConnectionEntry` model carries the process path but `KumoCoreKit` does
not depend on AppKit.

The Overview metric cards are interactive summaries. They use native `Button`
controls to navigate into the relevant sidebar destinations and expose focused
context-menu actions such as refresh, proxy toggle, or opening the matching
settings page. The Traffic metric uses the controller `/traffic` WebSocket for
live upload and download speeds, matching Mihomo's `up` / `down` stream values
rather than deriving speed from connection snapshots.
Overview status pills stay on one horizontal row for quick scanning. They cover
Core, Profile, Mode, System Proxy, and TUN; the TUN pill uses the same
`KumoCoreKit.setTunEnabled` path as the Configure page instead of keeping
separate SwiftUI state.
The stopped-core state is not repeated as a separate Overview card because the
toolbar action, Core pill, and connection metric already communicate that
state. When the core is running with no proxy groups, Overview still shows a
single inline empty state so the user has a clear next step.

Overview proxy group menus are intentionally bounded. They provide quick access
to the first visible proxy choices and route large groups to the full Proxies
page instead of creating oversized status menus.

The Configure views may begin as small setting surfaces, but user-visible controls must correspond to shared `KumoCoreKit` behavior. Do not add a SwiftUI-only setting that bypasses the runtime builder, state store, or controller facade.
System-facing configuration forms such as Core runtime settings and System
Proxy settings should stage edits in local SwiftUI state and commit them through
explicit Apply actions. This avoids writing partially typed ports, hosts, or
network service names into the shared controller layer.
The TUN settings page follows the same pattern for stack, routing, MTU, DNS
hijack, DNS resolver, ICMP forwarding, and route-exclude edits. The TUN enable
toggle remains an immediate runtime action, while staged advanced settings are
applied through `KumoCoreKit.applyTunSettings`; if Mihomo is running, Kumo
restarts the core so the generated runtime YAML and actual TUN interface state
match the form.

`SubStoreView` is a fully native SwiftUI surface that talks to the bundled
Sub-Store backend over HTTP. When the backend is reachable the view shows a
single thin toolbar with a `Subscriptions`/`Collections` segmented picker, an
overflow `⋯` menu (advanced screens, restart, stop, open log), and a backend
connection settings popover. The two primary sections each render their own
list-detail layout. Power-user surfaces (Files, Modules, Artifacts, Archives,
Share Tokens, Server Settings, Backend Logs) are presented on demand as sheets
launched from the overflow menu rather than living in a permanent sidebar, so
the default screen stays focused on subscriptions. Sub-Store data is cached in
a dedicated `@Observable` `SubStoreStore` so updates do not invalidate the rest
of the app. There is no embedded web view: management lives entirely in
SwiftUI, and the bundled Node sidecar continues to serve the JSON API. When the
backend is not running (or resources are not yet installed), `SubStoreView`
falls back to a `ContentUnavailableView` with the appropriate Start/Prepare
action so users never see an empty management chrome.

`AgentSkillsView` installs Kumo's bundled `kumo-cli` Agent Skill into supported
coding-agent skill directories. The target list, supported scopes, destination
paths, install state, and overwrite rules come from
`KumoCoreKit.AgentSkillsInstaller`, matching `kumo skills`.

## Liquid Glass Usage

Liquid Glass is used sparingly:

- Status cards
- Interactive proxy chips
- Main grouped controls

The implementation provides fallback material backgrounds for older macOS versions. Interactive glass is only used on controls that perform actions.

`KumoGlassSurfaceModifier` always passes a `tint: Color` (default `.clear`) so SwiftUI can interpolate hover / selection tints across state changes without rebuilding the modifier chain.

Sub-Store follows the same rule: backend status and connection-settings cards
use glass surfaces, while detail panes and editor sheets stay on plain native
materials so high-density list/detail content remains legible.

## Settings Surface

`SettingsView` is a two-tab `TabView` reserved for app-level preferences, with
About available as a separate window. Runtime status belongs in the main window
and status item menu instead of Settings:

- **General** — `Open at Login` (driven by `SMAppService.mainApp`) and `Quit when last window closes` (read by `applicationShouldTerminateAfterLastWindowClosed`).
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
- **Notifications (local + APNs-compatible)** — `AppNotificationCoordinator` registers update categories/actions (`Install Now`, `Remind Me Later`, `Restart Now`) and posts replacement-style update notifications. `KumoAppDelegate` handles notification responses and routes actions into `KumoAppStore.handleNotificationAction(...)`, so local and remote notifications share the same category/action contract.

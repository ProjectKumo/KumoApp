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
- `UNUserNotificationCenter` integration for update notifications: a five-minute runtime release-manifest poll, update-available prompts, install progress stage updates, and actionable buttons routed back to `KumoAppStore`.

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

Overview is a two-pane layout (`HSplitView`) inspired by single-window utility
apps. The left pane is a searchable proxy node list grouped by
`ProxyGroup`; each row shows a country flag inferred from the node `name` plus
a delay pill (green < 300 ms, orange otherwise, red on timeout, `—` when
unknown). When the inferred flag came from an emoji embedded in the node name,
the row text suppresses that embedded flag so the sidebar does not render the
same country twice; the original node name is still used for selection, search,
and Mihomo API calls. Tapping a row commits via `KumoAppStore.selectProxy(group:proxy:)`,
and a per-group `speedometer` button triggers `testDelay(for:)`. Typing in the
sidebar search field filters node names and force-expands every matching group
so users do not have to click twice to see hits.

Country flags resolve in three layers, in order:

1. **Name parsing** (`KumoCoreKit.ProxyCountry`) — a pure value-type helper
   that first returns any flag emoji already embedded in the name, then
   falls back to a two-phase keyword match. Phase 1 scans long keywords
   (ICU localized region names from `en_US / zh_Hans / zh_Hant / ja_JP`,
   plus a tiny `manualAliases` list for forms ICU does not return such as
   `USA / UK / 香港 / 狮城`). Phase 2 splits the name into ASCII letter
   tokens and resolves the first one that matches an ISO 3166-1 alpha-2
   code, disambiguating ambiguous names like `us-la-02` toward `US`.
2. **GeoIP fallback** (`ProxyNode.detectedCountry`) — when name parsing
   returns nothing, the UI renders the country code asynchronously filled
   in by `KumoCoreKit.ProxyGeoLookup`. The store reads the current
   profile's YAML through `ProfileNodeParser` to get `[name → server]`,
   then the lookup actor resolves each server to a country code via
   `ipwho.is` (HTTPS, accepts both IPs and hostnames), caching results to
   `~/Library/Application Support/Kumo/proxy-geo-cache.json` with a 30-day
   TTL and a 5-minute failure cooldown. Concurrent requests dedupe and
   coalesce, so a profile with thousands of nodes sharing 50 unique
   servers makes 50 HTTP calls, not thousands.
3. **`globe` SF Symbol placeholder** — shown only when both layers come up
   empty. We never invent a country.

`ProxyCountry` is in `KumoCoreKit` so CLI or tests can reuse the same
heuristic; unit coverage lives in `Tests/KumoCoreTests/ProxyCountryTests.swift`,
`ProfileNodeParserTests.swift`, and `ProxyGeoLookupTests.swift` and covers
embedded-flag passthrough, ISO / English / CJK keyword hits, ASCII boundary
false positives, Phase 2 token disambiguation, YAML edge cases, and the
lookup actor's cache + cooldown + dedup behaviour.

When the core is stopped, the Overview sidebar does not collapse to an empty
state. It renders a read-only preview of the user's `proxy-groups:` parsed
offline by `ProfileNodeParser.parseProxyGroups(yaml:)` into
`KumoAppStore.profilePreviewGroups`. The preview is refreshed after
`refreshProfiles()` and `loadProxyGroups()` so it stays consistent with the
selected profile. The sidebar dims the rows to ~55 % opacity and disables
row tap, context menus, and per-group `speedometer` actions; flags continue
to resolve from `ProxyCountry` plus any cached `detectedCountry` lookups.
Selection state is intentionally not displayed in the preview because
mihomo decides the actual selection at startup (saved selections,
URLTest / Fallback group types) and showing the YAML default would be
misleading. The moment the core transitions to `running`, the sidebar
swaps in the live `proxyGroups` from `/proxies` without rearranging rows
because both sources sort by `name.localizedCaseInsensitiveCompare`.

The stopped state is no longer surfaced as an in-pane banner — the toolbar
Start / Stop button, menu bar status item, and the cards on the right pane
(zero traffic, profile metadata still visible) already communicate it.
Failures, however, do escalate: `KumoAppStore.startCore` / `stopCore` post a
macOS system notification through `AppNotificationCoordinator`
(`postCoreStartFailed(error:)` / `postCoreStopFailed(error:)`, category
`CORE_STATE`) so the user notices even when the main window is occluded.
Successful start / stop is not notified — the UI already reflects it.

The right pane stacks four Liquid Glass cards using `kumoGlassCard`. Start /
stop and the mode picker are intentionally not duplicated here because the
toolbar already owns them:

- A **Profile** card with the current profile's name, `sourceDescription`,
  kind capsule (`Local` / `Remote` / `Inline`, plus `Sub-Store` when
  `isSubStoreManaged`), relative-time `updatedAt`, auto-update interval,
  and — for remote subscriptions that report `subscriptionUserInfo` — a
  used / total `ProgressView` plus optional expiry date. Bottom row exposes
  a `Refresh` button calling `refreshProfile(_:)` and a deep link to the
  Profiles destination via `onNavigate(.profiles)`.
- A **Traffic** card with vertical `↑ Upload` / `↓ Download` rows sourced
  from `KumoAppStore.trafficSnapshot`, which is fed by the controller
  `/traffic` WebSocket. Stopped reads as `0 KB/s` on both rows — a calm
  signal that nothing is flowing. The card is collapsible: tapping the
  header reveals an 80pt-tall `Charts.AreaMark` sparkline of combined
  throughput over the last 60 seconds (sparkle-style — monotone curve,
  vertical accent-color gradient, no axes / legend). The chart reads from
  `KumoAppStore.trafficHistory`, a rolling 60-sample buffer appended in
  the existing `startTrafficStream()` snapshot handler and cleared on
  `stopTrafficStream()` / `stopCore()`. When the buffer is empty (core
  hasn't run this session) the expanded area shows a "Start Kumo to see
  traffic history" placeholder so the card doesn't pop.
- A **System Proxy** card that exposes the master `Toggle` directly
  (`setSystemProxyEnabled`), shows endpoint, mode, and network service from
  `status.systemProxySettings`, and deep-links to the Configure page for
  staged edits.
- A **TUN** card with the master `Toggle` (`setTunEnabled`), stack / auto-route
  summary from `status.runtimeSettings.tun`, the last error from `tunStatus`
  when present, and the same deep-link affordance.

Detailed staged-edit forms still live in `SystemProxyView` and `TunView` (see
Configure). Overview only exposes the immediate enable toggles so the daily
workflow stays one click away from start, stop, mode switch, system proxy,
and TUN.

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

### List & dictionary fields use native +/- editors

Every list-shaped configuration field is rendered with the native macOS
list/table editor exposed by `EditableListComponents.swift`. Users add rows
with the `+` button at the bottom of the list, remove them with `−` or the
Delete key after selection, and edit each entry inline — no more comma- or
newline-separated free-text. Three editors share this affordance:

- `EditableStringList` — `[String]` values. Used by System Proxy bypass,
  TUN `dns-hijack` and route-exclude CIDR, Sniffer `skip-domain` /
  `force-domain` / `skip-dst-address` / `skip-src-address`, DNS
  `fake-ip-filter` / `default-nameserver` / `nameserver` /
  `proxy-server-nameserver` / `direct-nameserver` / `fallback`, and the
  Sub-Store subscription URL list, file URL list, subscription tags, and
  collection tag-based picks.
- `EditableIntList` — `[Int]` values with 1–65535 range expectations. Used
  by Sniffer HTTP / TLS / QUIC port lists.
- `PolicyDictEditor` and `FallbackFilterDictEditor` — `[String:
  PolicyValue]` and `[String: FallbackFilterValue]`. Used by DNS
  `nameserver-policy`, `proxy-server-nameserver-policy`, `hosts`, and
  `fallback-filter`. Each row shows the key plus a one-line value summary;
  the `+` / pencil button opens a sheet that switches between Single,
  Multiple, and (for fallback-filter) Boolean modes so the underlying
  Mihomo schema round-trips cleanly.

Free-form `TextEditor` instances remain only for documents that are not
lists: PAC scripts, Profile YAML, override content, Sub-Store module and
file bodies, Sub-Store server-settings JSON, and `ProcessPipelineEditor`
argument JSON.

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

- **General** — `Open at Login` (driven by `SMAppService.mainApp`), `Quit when last window closes` (read by `applicationShouldTerminateAfterLastWindowClosed`), and a Setup section with `Run Setup Again` plus a `Command Line Tool` row (install/remove `/usr/local/bin/kumo`).
- **Updates** — channel picker, optional manifest URL override, and GitHub Releases update checks backed by `AppUpdateManager`.
- **About Kumo window** — app icon, version/build, author GitHub link, project links, and the same update-check state used by Settings.

Preferences persist to `~/Library/Application Support/Kumo/preferences.json` via `UserPreferencesStore`. See [Persistence and Logging](../operations/persistence-logging.md) for fields.

## First-Run Onboarding

`OnboardingView` is a four-step sheet attached to `KumoRootView` and gated by
`UserPreferences.hasCompletedOnboarding`. It walks the user through optional
helpers without forcing any of them:

1. **Welcome** — short feature summary; users can dismiss with Skip.
2. **Command Line Tool** — calls `KumoController.cliLinkStatus()` and offers
   `Install` (or `Remove`) for the `/usr/local/bin/kumo` symlink. The install
   step triggers a macOS administrator authorization prompt via `osascript`
   because the default `/usr/local/bin` requires elevated privileges.
3. **Agent Skill** — lists every `AgentSkillsTarget`, all unselected by
   default, and installs the bundled Kumo skill into each selected agent's
   `~/.<agent>/skills` directory through `AgentSkillsInstaller`.
4. **Done** — summarises what was installed and saves
   `hasCompletedOnboarding = true` through `KumoAppStore.completeOnboarding()`.

Settings exposes `Run Setup Again` (`KumoAppStore.reopenOnboarding()`) so users
can rerun the flow without resetting the persisted flag. The sheet is also the
preferred path for installing the CLI — direct symlinks created outside Kumo
are still detected, but the GUI step is the documented entry point.

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
- **Notifications** — `AppNotificationCoordinator` registers update categories/actions (`Install Now`, `Remind Me Later`, `Restart Now`) and posts local update notifications fed by the five-minute release-manifest poll documented in [App Updates](../operations/app-updates/README.md). `KumoAppDelegate` handles notification responses and routes actions into `KumoAppStore.handleNotificationAction(...)`.

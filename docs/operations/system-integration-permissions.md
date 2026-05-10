# System Integration and Permissions

## App Bundle and Entitlements

Kumo ships as a real `.app` bundle generated from `project.yml` via XcodeGen
(`make generate`). The bundle pulls in:

- `Resources/KumoApp/Info.plist` — bundle metadata, `LSApplicationCategoryType`,
  `NSAppTransportSecurity` (allows local-network PAC), `NSServices` (Services
  menu), `CFBundleDocumentTypes` (`.yaml` profiles), `NSUserActivityTypes`
  (Spotlight handoff), and `NSAppleEventsUsageDescription` /
  `NSSystemAdministrationUsageDescription` (consent strings used when running
  `networksetup` and spawning the Mihomo / Sub-Store helper processes).
- `Resources/KumoApp/KumoApp.entitlements` — `com.apple.security.app-sandbox`
  is **disabled** so that `networksetup` invocations and child processes
  (Mihomo core, Sub-Store backend, PAC HTTP listener) keep working without a
  separate helper. `com.apple.security.network.client` and
  `com.apple.security.network.server` are enabled. Sandboxing remains a
  follow-up once helper-bundle / XPC architecture lands.

Build commands:

```bash
make generate    # xcodegen generate -> Kumo.xcodeproj (gitignored)
make app         # xcodebuild Debug -> build/Build/Products/Debug/Kumo.app
make app-release # xcodebuild Release
make dev         # build + open Kumo.app
make dev-cli     # legacy swift run KumoApp without bundle (no Spotlight / Intents)
```

## System Proxy

`SystemProxyController` runs macOS `networksetup` commands and now branches on
the `SystemProxyMode` carried by `SystemProxyConfiguration`:

- `manual` mode configures web, secure web, SOCKS firewall proxies, plus the
  bypass list, and explicitly turns auto-proxy state off.
- `pac` mode boots a local `PACServer` (loopback `NWListener` HTTP that
  responds with the user's PAC script as
  `application/x-ns-proxy-autoconfig`), then runs `-setautoproxyurl
  http://127.0.0.1:<port>/proxy.pac` and `-setautoproxystate on`, while
  turning manual web/secure/socks off.
- `setEnabled(false)` stops the PAC server and turns both manual and PAC
  states off.

`setSystemProxy(_:dryRun:)` is `async` — dry-run mode skips the listener and
returns the would-be commands for inspection (used by the CLI and tests).

## LaunchAgent (Open at Login)

`KumoAppDelegate` keeps `SMAppService.mainApp` in sync with
`UserPreferences.launchAtLogin` whenever the app launches. The Settings
"Preferences" tab toggles the same preference and registers/unregisters
through `SMAppService`. Registration only succeeds when `Kumo.app` lives in
`/Applications` (macOS launch services requirement).

## Dock Badge

While the app is running, a 1 s timer in `KumoAppDelegate` writes
`NSApp.dockTile.badgeLabel` from the live `KumoAppStore.connections.count`,
so the user sees connection volume even when the main window is hidden.

## Spotlight

`SpotlightIndexer` indexes profile summaries (name + source) into the default
`CSSearchableIndex` on launch and after profile refreshes. Each entry uses
the profile id as `uniqueIdentifier`, and `NSUserActivityTypes` declares
`io.kumo.KumoApp.openProfile`. Tapping a Spotlight result returns the user
to Kumo and selects the matching profile via `KumoAppContext.handleUserActivity`.

## Services Menu

`Info.plist` registers a single Services entry — "Import Profile to Kumo" —
that targets `importProfileURL(_:userData:error:)` on the AppDelegate. Any
text or URL string sent through Services becomes a profile import attempt
via `KumoAppStore.importRemoteProfile(urlString:useProxy:)`.

## App Intents

`KumoIntents.swift` exposes five intents that surface in Shortcuts, Siri,
and Spotlight:

- `StartKumoIntent` / `StopKumoIntent`
- `RefreshKumoIntent`
- `SetKumoModeIntent` (with `KumoModeChoice` enum mirroring `OutboundMode`)
- `ToggleSystemProxyIntent`

Phrases are wired through `KumoShortcutsProvider`. Each intent resolves the
live `KumoAppStore` via `KumoAppContext.shared.store`, so intent
side-effects stay consistent with the SwiftUI UI.

## Dry Run

`setSystemProxy(_:dryRun:)` (now `async`) still supports dry-run for unit
tests, CLI previews, agent safety, and debugging network service names.
Dry-run returns the exact commands without executing them and without
binding the PAC listener.

## Current Assumptions

The default network service is `Wi-Fi`. This is not universal.
`SystemProxyController` lists network services through
`networksetup -listallnetworkservices`; the UI should consume that for a
production picker.

When enabling system proxy outside dry-run, Kumo captures the previous
proxy state for the selected service. The disable path turns Kumo-managed
manual and auto-proxy states off; a later service-backed pass should
restore exact previous values from the snapshot.

## Permissions

Kumo still avoids a privileged helper. Features that need elevated
privileges remain behind Advanced settings until the service design is
ready. App Sandbox stays off until a helper-bundle XPC route is in place.

## Advanced Features

The following remain non-primary features:

- TUN device setup
- DNS overwrite
- System proxy guard and auto-restore
- Privileged helper installation
- LaunchDaemon management (we currently use `SMAppService.mainApp` only)

## Future Work

- Restore exact previous proxy settings from the captured snapshot.
- Add a proxy guard in service mode.
- Add a signed privileged helper for TUN and protected system changes.
- Adopt App Sandbox + helper-bundle separation so `networksetup` invocations
  and child processes can run from a sandboxed front-end.

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

Before enabling system proxy, Kumo now verifies that the target
`host:mixed-port` is accepting local TCP connections. This prevents macOS from
being pointed at a stale or failed listener. After applying `networksetup`
commands, Kumo reads the OS proxy state back and only marks the feature enabled
when manual or PAC settings match the requested mode.

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

Kumo can still store a manual network service name, but new default system
proxy settings prefer the active route interface by resolving
`route -n get default` through `networksetup -listnetworkserviceorder`.
This avoids writing proxy settings to `Wi-Fi` when the active service is
Ethernet, USB tethering, or another macOS network service.

When enabling system proxy outside dry-run, Kumo captures the previous
proxy state for the selected service. The disable path turns Kumo-managed
manual and auto-proxy states off; a later service-backed pass should
restore exact previous values from the snapshot.

## Permissions

Kumo now has the model and command surface for service mode, including signed
service requests, service status, TUN status, and a `KumoService` helper target.
This follows the Sparkle and Clash Verge Rev model: macOS asks for administrator
authorization when Kumo installs or repairs the helper, but Kumo does **not**
register a NetworkExtension or VPN profile. The "Allow VPN Configuration"
system prompt is therefore not expected for System Proxy or Mihomo TUN mode.

Until the helper or a privileged process is available, TUN enable requests fail
with a visible service-mode error instead of leaving the UI in a misleading
"On" state. Once installed, the helper owns privileged operations such as
starting Mihomo for TUN and applying guarded system proxy changes.

## Advanced Features

The following remain hardening work after the first service-backed path:

- System proxy guard and auto-restore
- Privileged helper repair UX
- LaunchDaemon management hardening and notarized distribution

## Future Work

- Restore exact previous proxy settings from the captured snapshot.
- Add a proxy guard in service mode.
- Harden the signed privileged helper installer for TUN and protected system
  changes, including notarized app distribution.
- Adopt App Sandbox + helper-bundle separation so `networksetup` invocations
  and child processes can run from a sandboxed front-end.

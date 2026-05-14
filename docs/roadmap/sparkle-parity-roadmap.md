# Sparkle Parity Roadmap

Kumo tracks Sparkle as a product-capability reference, not as an Electron
implementation target. The goal is to keep Kumo native to macOS while reaching
equivalent coverage for Mihomo control, system integration, diagnostics,
updates, and backup workflows.

## Status Legend

- `implemented`: usable through shared `KumoCoreKit` behavior.
- `partial`: a visible or persisted surface exists, but parity is incomplete.
- `planned`: no complete implementation yet, but the architecture has a place
  for it.
- `deferred`: intentionally postponed until a prerequisite is stable.

## Capability Matrix

| Area | Capability | Kumo Status | Primary Kumo Owner | Acceptance Point |
| --- | --- | --- | --- | --- |
| Core | Local Mihomo process start/stop/restart | implemented | `CoreSupervisor` | `kumo start --json`, `kumo stop --json`, and stale PID recovery work. |
| Core | Managed Mihomo core install | partial | `CoreInstaller` | Stable and preview channels can install, verify, cache, and report versions. |
| Core | Startup readiness states | partial | `CoreSupervisor` | UI can distinguish launched, controller ready, providers ready, and failed. |
| Core | Graceful shutdown with timeout escalation | implemented | `CoreSupervisor` | Stop attempts graceful termination before force kill, uses a PID file fallback, and persists failures. |
| Runtime | Structured runtime config merge | implemented | `RuntimeConfigBuilder` | Profile, overrides, and Kumo-owned keys merge with deterministic precedence. |
| Runtime | Config cleanup and normalization | planned | `RuntimeConfigBuilder` | Empty/default Mihomo fields are removed before writing runtime YAML. |
| Profiles | Local profile import and edit | implemented | `ProfileRepository` | Local YAML can be imported, edited, selected, and deleted safely. |
| Profiles | Remote profile refresh | implemented | `ProfileRepository` | Remote subscriptions refresh manually and on due intervals. |
| Profiles | Subscription metadata retention | partial | `ProfileRepository` | Headers persist name, home URL, update interval, user info, UA, and fingerprint. |
| Overrides | Ordered YAML overrides | partial | `OverrideRepository` | Global and profile-scoped YAML overrides apply in documented order. |
| Overrides | JavaScript transforms | deferred | `OverrideRepository` | Requires a reviewed sandbox strategy before enablement. |
| Controller | Proxy groups and selection | implemented | `MihomoControllerClient` | Groups load, filter hidden entries, and allow node selection. |
| Controller | Outbound mode switching | implemented | `KumoAppStore` / `MihomoControllerClient` | Rule / Global / Direct changes persist locally, PATCH Mihomo `/configs`, close existing connections, and refresh proxy groups without blocking the Start / Stop toolbar action. |
| Controller | Rules, connections, providers, geo updates | partial | `MihomoControllerClient` | Inspect and Configure pages expose controller actions without direct UI clients. |
| Controller | Traffic, memory, logs, and lifecycle events | partial | `MihomoControllerClient` | Event streams use bounded caches and survive transient disconnects. |
| CLI | Stable agent-friendly JSON commands | partial | `KumoCLI` | Every command has `--json`, stable envelopes, and deterministic exit codes. |
| System Proxy | Manual macOS system proxy | implemented | `SystemProxyController` | Dry-run and real commands configure web, secure web, and SOCKS proxy. |
| System Proxy | Active service detection and restore | planned | `SystemProxyController` | Kumo detects network services and restores previous proxy settings on disable. |
| System Proxy | PAC hosting and guard | planned | `SystemProxyController` / `KumoService` | PAC and auto-restore run only after service-mode support exists. |
| Service | Privileged service backend | planned | `KumoService` | GUI and CLI can switch backend without public command changes. |
| Service | Signed local service requests | planned | `KumoService` | Requests use key material, timestamps, nonces, and body hashing. |
| Sub-Store | Persisted configuration | implemented | `SubStoreManager` | Status, local resource version, backend port, cron settings, proxy mode, LAN mode, and custom backend settings persist. |
| Sub-Store | Local lifecycle management | implemented | `SubStoreManager` / `SubStoreSupervisor` | Bundled Node sidecar + `sub-store.bundle.js` are prepared on demand; Kumo starts, stops, and restarts the backend. |
| Sub-Store | Native management UI | implemented | `KumoApp.SubStoreView` / `SubStoreClient` | SwiftUI surfaces subscriptions, collections, files, modules, artifacts, archives, tokens, settings, and logs by talking to the backend over HTTP. |
| Resources | Proxy/rule provider management | partial | `MihomoControllerClient` | Providers list, update, and show useful metadata in Configure. |
| Diagnostics | Connections and logs inspection | partial | `MihomoControllerClient` / `KumoAppStore` | Active/closed connections, close actions, filtering, and live logs are available. |
| Backup | Export/import local state | planned | `KumoCoreKit` | Profiles, overrides, settings, Sub-Store status, and service settings round-trip. |
| Updates | App update channel and installer | planned | Distribution layer | Stable/beta app updates verify signatures and coordinate core/proxy state. |
| UI | Native Daily / Inspect / Configure IA | implemented | `KumoApp` | Advanced features remain secondary to the daily connection workflow. |
| UI | Sparkle-level advanced controls | partial | `KumoAppStore` / Views | Proxies, connections, rules, logs, profiles, and settings reach feature parity. |
| Quality | CoreKit unit tests | partial | `KumoCoreTests` | Runtime, profile, override, state, proxy, and controller mapping tests pass. |
| Quality | CLI, service, and UI store tests | planned | Tests | JSON snapshots, service auth/fallback, and store state transitions are covered. |

## Implementation Order

1. Stabilize the structured configuration pipeline and controller contract tests.
2. Expand runtime supervision and event streams while keeping local process mode
   as the default.
3. Add system proxy restore and service-ready abstractions before privileged
   service installation.
4. Build Sub-Store, backup, update, and advanced UI features on the stabilized
   control layer.
5. Raise release quality with CLI snapshots, service tests, migration tests,
   and manual QA checklists.

## Non-Goals

- Do not port Sparkle's Electron renderer or giant IPC surface.
- Do not add JavaScript overrides until sandboxing and audit behavior are
  explicitly designed.
- Do not make TUN, PAC guard, or privileged networking part of the primary
  daily workflow before service mode is ready.

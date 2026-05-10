# Service Mode Roadmap

## Why Service Mode Exists

The first version can run without a privileged service. That keeps development simple and avoids asking for unnecessary permissions. Service mode becomes valuable when Kumo needs stronger lifecycle guarantees or privileged networking features.

## Reference Model

The Sparkle reference project uses a separate service process with:

- Unix socket communication
- Request signing
- Core start and stop endpoints
- Core event streams
- System proxy endpoints
- Fallback to non-service mode when service is unavailable

Kumo follows the same separation of concerns in Swift-native form. The helper
path uses administrator authorization and LaunchDaemon registration; it does
not use NetworkExtension or install a VPN configuration profile.

## Proposed API Shape

`KumoService` endpoints mirror current `KumoCoreKit` intent:

- `GET /status`
- `POST /core/start`
- `POST /core/stop`
- `POST /core/restart`
- `PATCH /core/mode`
- `PUT /core/proxies/{group}`
- `GET /core/events`
- `GET /sysproxy/status`
- `POST /sysproxy/enable`
- `POST /sysproxy/disable`
- `GET /service/status`
- `POST /service/install`
- `POST /service/uninstall`
- `GET /tun/status`
- `POST /tun/enable`
- `POST /tun/disable`

The GUI and CLI should keep their public command semantics unchanged.

## Authentication

The service does not trust arbitrary local clients. `KumoServiceRequestSigner`
defines the Swift-side canonical request and HMAC header shape used by the
Unix socket transport:

- A generated shared secret persisted in Kumo Application Support.
- Request timestamps and nonces.
- Request body hashing.
- A canonical signing string.

## Migration Strategy

1. Keep local `KumoCoreKit` implementations as the default.
2. Add service client protocols with the same high-level operations.
3. Introduce `KumoService` as an optional backend.
4. Keep TUN guarded by service availability: if no helper or privileged process
   is available, Kumo records the failure and rolls the TUN setting back.
5. Switch GUI and CLI to service-backed calls when service mode is enabled.
6. Preserve CLI output schemas.

## Remaining Helper Work

- Harden LaunchDaemon installation for notarized release artifacts.
- Improve automatic service repair and diagnostics.
- Expand proxy guard events and UI notifications.
- Move PAC hosting fully into the helper process for long-lived service mode.

The current implementation adds the service-mode model, signed endpoint
surface, CLI/UI status, administrator-authorized `KumoService` installation,
Unix socket request routing, service-backed core/system proxy/TUN control, and
TUN configuration generation. It intentionally does not silently install a
privileged daemon; installation remains an explicit, authorized user action.

## Status of Local Subsystems (Phase B)

Phase B brings several locally hosted subsystems into the app process,
without introducing the privileged service. Each is documented here so the
service-mode migration can absorb them later without scope surprises.

- **PAC mode is implemented** via `PACServer` (NWListener HTTP loopback) +
  `networksetup -setautoproxyurl`. When a privileged service exists, this
  listener should move into the service process and the front-end should
  request "PAC enabled" rather than hosting the listener directly.
- **Sub-Store backend supervisor is implemented** via `SubStoreSupervisor`
  (`Process` lifecycle + `logs/substore.log`). The future service should
  own this process so the GUI can be quit without killing Sub-Store.
- **Open at Login** uses `SMAppService.mainApp`. Once a helper bundle
  exists, switch to a `SMAppService.daemon`/`agent` registration so the
  service can run independently of the UI.
- **Spotlight indexing** uses `CSSearchableIndex.default()` from the app
  process. This works without a service; only the data source has to move
  if profile state is later owned by the service.
- **App Intents** call back into `KumoAppStore`. Behind a service, these
  should hit the same JSON service endpoints documented above so intents
  keep working when the GUI is closed.
- **TUN mode** now has first-class settings in `CoreRuntimeSettings`. When
  enabled behind service availability, runtime config generation owns the
  `tun:` and required `dns:` blocks and the helper restarts Mihomo from the
  privileged backend. When service mode is unavailable, Kumo disables the
  requested TUN state and surfaces the helper requirement.

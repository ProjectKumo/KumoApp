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

Kumo should follow the same separation of concerns, but implement it in Swift-native form.

## Proposed API Shape

Future `KumoService` endpoints should mirror current `KumoCoreKit` intent:

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

The GUI and CLI should keep their public command semantics unchanged.

## Authentication

The service should not trust arbitrary local clients. `KumoServiceRequestSigner`
now defines the Swift-side canonical request and HMAC header shape for the
future service client. A future version should use:

- A generated key pair or shared secret.
- Request timestamps and nonces.
- Request body hashing.
- A canonical signing string.

## Migration Strategy

1. Keep local `KumoCoreKit` implementations as the default.
2. Add service client protocols with the same high-level operations.
3. Introduce `KumoService` as an optional backend.
4. Switch GUI and CLI to service-backed calls when service mode is enabled.
5. Preserve CLI output schemas.

## Out of Scope for v1

- LaunchDaemon installation.
- Privileged TUN setup.
- Signed helper authorization flows.
- Automatic service repair.

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

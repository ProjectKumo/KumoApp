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

The service should not trust arbitrary local clients. A future version should use:

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

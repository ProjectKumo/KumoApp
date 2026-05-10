# Mihomo Runtime and Controller

## Runtime Model

Kumo manages a Mihomo core executable. The core can come from:

- A path passed to the CLI with `--core`.
- The `KUMO_MIHOMO_PATH` environment variable.
- A bundled `mihomo` resource.
- Common Homebrew or system paths.

The current implementation starts Mihomo with a generated work directory. The generated `config.yaml` contains Kumo-controlled controller and proxy settings.

## Process Supervision

`CoreSupervisor` handles:

- Preparing application support directories.
- Writing the runtime configuration.
- Starting Mihomo with `Process`.
- Recording the process identifier in state.
- Stopping a running process with a graceful signal escalation path.
- Detecting stale process identifiers.
- Recording runtime lifecycle events.

This is still a local-process supervisor. It does not yet implement automatic restart, service takeover, or privileged TUN setup.

## Controller Client

`MihomoControllerClient` wraps the Mihomo external-controller API:

- `GET /version`
- `GET /configs`
- `PATCH /configs`
- `GET /proxies`
- `PUT /proxies/{group}`
- `GET /proxies/{proxy}/delay`
- `GET /rules`
- `GET /connections`
- `DELETE /connections`
- `DELETE /connections/{id}`
- `GET /traffic` over WebSocket
- `GET /memory` over WebSocket

It maps proxy groups into `ProxyGroup`, proxy names into `ProxyNode`, rules into `RuleEntry`, and connections into `ConnectionEntry`.

## Sparkle-Parity Controller Surface

The following external-controller endpoints are planned for the Configure and Inspect pages:

- `PATCH /rules/disable`
- `GET /providers/proxies`
- `PUT /providers/proxies/{name}`
- `GET /providers/rules`
- `PUT /providers/rules/{name}`
- `POST /upgrade/geo`
- `GET /logs` over WebSocket or an equivalent streaming transport

## Current Transport

The first implementation uses local HTTP through `URLSession`. The architecture leaves room for Unix socket transport, which is useful for matching the Sparkle-style service model later.

## Error Handling

Controller failures are surfaced as `KumoError.controllerResponse(status, body)` when the response is not successful. UI and CLI callers should display the resulting message without hiding the HTTP status.

## Future Work

- Add Unix socket controller transport.
- Add resilient reconnect policies for event streams.
- Add restart policies.
- Add provider initialization progress.
- Add provider update and preview APIs.
- Add structured log streaming and cache limits.

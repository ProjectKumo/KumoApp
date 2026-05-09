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
- Stopping a running process with `SIGTERM`.
- Detecting stale process identifiers.

This is a first-version supervisor. It does not yet implement automatic restart, service takeover, or privileged TUN setup.

## Controller Client

`MihomoControllerClient` wraps the Mihomo external-controller API:

- `GET /version`
- `GET /configs`
- `PATCH /configs`
- `GET /proxies`
- `PUT /proxies/{group}`

It maps proxy groups into `ProxyGroup` and proxy names into `ProxyNode`.

## Current Transport

The first implementation uses local HTTP through `URLSession`. The architecture leaves room for Unix socket transport, which is useful for matching the Sparkle-style service model later.

## Error Handling

Controller failures are surfaced as `KumoError.controllerResponse(status, body)` when the response is not successful. UI and CLI callers should display the resulting message without hiding the HTTP status.

## Future Work

- Add Unix socket controller transport.
- Add event streams for logs, traffic, and core lifecycle.
- Add startup readiness detection.
- Add restart policies.
- Add provider initialization progress.

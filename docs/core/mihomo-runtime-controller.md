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

This is still available as the local-process fallback. When Kumo Helper is
installed and reachable, `KumoController` routes start, stop, restart, system
proxy, and TUN operations through the signed Unix socket service backend so the
privileged helper owns Mihomo.

## TUN Runtime Settings

`CoreRuntimeSettings` can carry `TunSettings`. When TUN is enabled and service
mode is available, `RuntimeConfigBuilder` removes profile-provided `tun`/`dns`
top-level blocks and appends Kumo-controlled TUN and DNS settings:

- `tun.enable`
- `tun.stack`
- `tun.auto-route`
- `tun.auto-detect-interface`
- `tun.strict-route`
- `tun.dns-hijack`
- `tun.mtu`
- `dns.enable`
- `dns.enhanced-mode`
- `dns.fake-ip-range`
- `dns.nameserver`

On macOS, Kumo only writes a configured TUN device name when it already starts
with `utun`, matching the platform's virtual interface naming rules. If no
privileged helper or privileged process is available, TUN enable requests are
rejected and the stored state is rolled back before Mihomo is restarted.

When Kumo Helper is running, `POST /tun/enable` updates the same runtime
settings, rewrites the controlled config, restarts the helper-owned Mihomo
process, waits for the controller to become ready, and reports the resulting
`TunStatus`. The macOS authorization involved is helper installation/repair,
not a NetworkExtension VPN configuration prompt.

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

Local mode uses HTTP through `URLSession` to talk to Mihomo's external
controller. Service mode uses Kumo's signed Unix socket transport to ask
`KumoService` to perform privileged lifecycle operations, while the helper-owned
Mihomo process still exposes its normal external-controller API.

## Error Handling

Controller failures are surfaced as `KumoError.controllerResponse(status, body)` when the response is not successful. UI and CLI callers should display the resulting message without hiding the HTTP status.

## Future Work

- Add resilient reconnect policies for event streams.
- Add restart policies.
- Add provider initialization progress.
- Add provider update and preview APIs.
- Add structured log streaming and cache limits.

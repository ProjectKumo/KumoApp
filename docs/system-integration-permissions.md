# System Integration and Permissions

## System Proxy

The first version uses macOS `networksetup` commands to enable or disable proxy settings for a network service. `SystemProxyController` builds and runs these commands.

When enabled, Kumo configures:

- Web proxy
- Secure web proxy
- SOCKS firewall proxy

When disabled, Kumo turns those proxy states off.

## Dry Run

`setSystemProxy(_:dryRun:)` supports dry-run mode. This is important for:

- Unit tests
- CLI previews
- Agent safety
- Debugging network service names

Dry-run returns the exact commands without executing them.

## Current Assumptions

The default network service is `Wi-Fi`. This is not universal. A production UI should let users choose a network service or detect active services.

## Permissions

The v1 implementation avoids privileged helper installation. This keeps the first version easier to build and reason about. Features that need elevated privileges should remain behind Advanced settings until the service design is ready.

## Advanced Features

The following should not be primary v1 features:

- TUN device setup
- DNS overwrite
- System proxy guard and auto-restore
- Privileged helper installation
- LaunchDaemon management

## Future Work

- Detect available network services.
- Add safe restore of previous proxy settings.
- Add a proxy guard in service mode.
- Add a signed privileged helper for TUN and protected system changes.

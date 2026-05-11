<p align="center">
  <img src="Assets/KumoApp-Banner-1280x640.png" alt="Kumo app banner" width="640" style="border-radius: 24px;">
</p>

<h1 align="center">Kumo</h1>

<p align="center">
  <strong>A calm native macOS client for the <a href="https://github.com/MetaCubeX/mihomo">Mihomo</a> proxy core.</strong>
</p>

<p align="center">
  SwiftUI app · Agent-friendly CLI · Shared control layer
</p>

<p align="center">
  <a href="https://www.swift.org">
    <img alt="Swift 6.0" src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white">
  </a>
  <a href="https://www.apple.com/macos/">
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white">
  </a>
  <a href="https://github.com/MetaCubeX/mihomo">
    <img alt="Powered by Mihomo" src="https://img.shields.io/badge/core-Mihomo-0F766E">
  </a>
  <img alt="Status: active development" src="https://img.shields.io/badge/status-active%20development-2563EB">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#roadmap">Roadmap</a>
</p>

---

## Overview

Kumo is a Mac utility for connecting quickly without turning everyday proxy
management into a network operations dashboard. The first screen is designed to
answer four questions:

- Is Kumo connected?
- Which outbound mode is active?
- Is the macOS system proxy enabled?
- Which profile and proxy group are currently in use?

Advanced capabilities such as DNS, TUN, rule providers, logs, overrides, and
Sub-Store remain discoverable in secondary sections, so daily use stays focused.

## Features

| Area | What Kumo provides |
| --- | --- |
| Native macOS app | SwiftUI interface built around `NavigationSplitView`, `Settings`, an AppKit menu bar status item, and standard macOS controls. |
| Shared core | `KumoCoreKit` owns Mihomo lifecycle, profile generation, controller calls, state, and system proxy logic. |
| CLI for humans and agents | The `kumo` executable supports stable command names, `--json`, dry-run system changes, and predictable exit codes. |
| Mihomo discovery | Kumo can use `--core`, `KUMO_MIHOMO_PATH`, a bundled binary, common Homebrew paths, or a managed install. |
| Safe defaults | Empty profiles generate a direct config, system proxy changes can be dry-run, and core logs are captured in one place. |
| Focused UI | Daily actions stay prominent while inspection and configuration tools remain available when needed. |

## Screenshots

The v1 SwiftUI layout is still being finalized. The current interface structure
is documented in [docs/interfaces/macos-swiftui-interface.md](docs/interfaces/macos-swiftui-interface.md).

## Quick Start

### Requirements

- macOS 15 Sequoia or later
- Xcode 16+ with the Swift 6.0 toolchain
- A Mihomo binary, either installed by Kumo or provided manually

### Build From Source

```bash
git clone https://github.com/ProjectKumo/KumoApp.git
cd KumoApp

# Build app, CLI, library, and tests
make swift-build

# Launch the SwiftUI app
make run-app

# Or run the CLI
make run-cli ARGS="status --json"
```

Kumo stores local state under `~/Library/Application Support/Kumo/`. You can
clear the development state with:

```bash
make reset-local-state
```

## Usage

### macOS App

Kumo opens with **Overview** selected. The sidebar is grouped by how often each
area is needed:

| Section | Destinations | Purpose |
| --- | --- | --- |
| Daily | Overview, Profiles, Proxies | Connection state, profile management, proxy groups, and node selection. |
| Inspect | Connections, Logs, Rules | Troubleshooting, traffic inspection, logs, and rule visibility. |
| Configure | Core, System Proxy, DNS, TUN, Sniffer, Resources, Overrides, Sub-Store | Lower-frequency runtime settings and advanced integrations. |

Quick controls are available from the menu bar status item and keyboard:

| Action | Shortcut |
| --- | --- |
| Start Kumo | `Shift` + `Command` + `S` |
| Stop Kumo | `Command` + `.` |
| Rule / Global / Direct mode | `Command` + `1` / `2` / `3` |
| Refresh | `Command` + `R` |
| Settings | `Command` + `,` |

### Command Line

The `kumo` executable uses the same `KumoCoreKit` facade as the app:

```bash
kumo status --json
kumo start --core /path/to/mihomo
kumo stop
kumo restart
kumo mode rule        # rule | global | direct
kumo proxies --json
kumo select "Proxy" "HK-01"
kumo profile refresh "https://example.com/sub.yaml"
kumo sysproxy on --dry-run --json
kumo core install
```

### Agent Contract

Commands that support JSON use a stable envelope:

```json
{
  "ok": true,
  "data": {},
  "error": null
}
```

Errors set `ok` to `false` and populate `error`. Exit code `0` means success;
exit code `1` means the command failed.

## Architecture

```text
┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│   KumoApp (SwiftUI)  │   │   KumoCLI (`kumo`)   │   │  KumoService (later) │
└──────────┬───────────┘   └──────────┬───────────┘   └──────────┬───────────┘
           │                          │                          │
           └────────────┬─────────────┴─────────────┬────────────┘
                        ▼                           ▼
                ┌────────────────────────────────────────┐
                │              KumoCoreKit               │
                │  Models · Profiles · Runtime · Net ·   │
                │  System proxy · Paths · State · Errors │
                └────────────────────────────────────────┘
                        ▼
                ┌────────────────────────────────────────┐
                │           Mihomo core (process)        │
                │  external-controller · mixed-port · ... │
                └────────────────────────────────────────┘
```

The control layer is the contract. UI surfaces call `KumoCoreKit` rather than
reimplementing Mihomo lifecycle, profile generation, or system proxy behavior.

### Repository Layout

```text
Sources/
  KumoCoreKit/   Shared domain, runtime, controller, and system integration code
    Models/         Core data types
    Configuration/  Profile loading and runtime config generation
    Runtime/        Mihomo process supervision and managed core install
    Networking/     Mihomo external-controller HTTP client
    System/         macOS networksetup-based system proxy controller
    Support/        Paths, state storage, shared errors
  KumoCLI/       Command-line frontend
  KumoApp/       SwiftUI macOS frontend
Tests/
  KumoCoreTests/ Unit tests for shared behavior
docs/            Technical documentation
Assets/          Project images and README assets
```

## Documentation

Project documentation lives under [docs/](docs/) and is grouped by domain:

- [Product](docs/product/README.md)
- [Interfaces](docs/interfaces/README.md)
- [Core](docs/core/README.md)
- [Operations](docs/operations/README.md)
- [Quality](docs/quality/README.md)
- [Roadmap](docs/roadmap/README.md)
- [Implementation Standards](docs/standards/README.md)

Agent-facing guidelines, including UI copy and SwiftUI component constraints,
live in [AGENTS.md](AGENTS.md).

## Development

### Common Commands

```bash
make help                   # List every available target
make swift-build            # swift build (debug)
make build-release          # swift build -c release
make run-app                # Launch the SwiftUI app
make run-cli ARGS="..."     # Run the CLI with arbitrary arguments
make cli-status             # kumo status --json
make cli-sysproxy-dry-run   # kumo sysproxy on --dry-run --json
make swift-test             # swift test
make xcode-build            # xcodebuild -scheme KumoApp
make xcode-test             # xcodebuild -scheme Kumo-Package test
make check                  # Build + test + verify CLI status output
make docs                   # List technical docs
make clean                  # swift package clean
make reset-local-state      # Remove local Kumo app state
```

### Local Data

```text
~/Library/Application Support/Kumo/
  profiles/
    default.yaml
  work/
    config.yaml      # Generated Mihomo runtime config
  logs/
    core.log         # Core stdout and stderr
  cores/
    mihomo           # Managed core binary
  state.json         # Shared state used by GUI and CLI
```

### Testing

The first test suite targets `KumoCoreKit`, where the shared behavior lives:

- Runtime config generation
- Core state persistence
- System proxy command construction in dry-run mode
- Profile repository behavior

Tests should not mutate real system state. Use temporary application support
directories, `--dry-run` for system proxy commands, and mocked controller
responses before testing live Mihomo APIs.

```bash
swift test
# or
make xcode-test
```

## Roadmap

Kumo's first version intentionally avoids privileged helpers. The broader plan
is tracked in [docs/roadmap/service-mode-roadmap.md](docs/roadmap/service-mode-roadmap.md):

- Runtime settings parity for ports, LAN access, log level, controller secret,
  and Geo data.
- Provider and rules management for refresh actions and rule hit details.
- Ordered YAML overrides, followed by a reviewed JavaScript transform sandbox.
- Sub-Store lifecycle, update flow, custom backend support, and WebView or
  external browser access.
- Service mode with a Swift-native service, Unix socket transport, and signed
  requests.
- Event streams for logs, traffic, and core lifecycle.
- Structural YAML merge for profile and runtime config.
- Network service detection for system proxy.
- CLI surface growth: `kumo logs`, `kumo doctor`, `kumo config path`, JSON
  schemas, and shell completion.

## Contributing

Contributions are welcome. Before opening a PR:

1. Read [AGENTS.md](AGENTS.md) for UI copy and SwiftUI component constraints.
2. Skim the document under [docs/](docs/) that relates to your change.
3. Keep `KumoCoreKit` independent from SwiftUI.
4. Run `make check` or `swift test`.
5. Update the relevant document under `docs/` when a change meaningfully alters
   product behavior, architecture, runtime configuration, persistence,
   permissions, testing expectations, or UI information architecture.

## Acknowledgements

- [Mihomo](https://github.com/MetaCubeX/mihomo), the proxy core Kumo drives.
- The Clash and Mihomo ecosystem, for the controller API conventions Kumo speaks.
- Apple, for SwiftUI, Liquid Glass, and the macOS Human Interface Guidelines.

## Star History

<a href="https://www.star-history.com/?repos=projectkumo%2Fkumoapp&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=projectkumo/kumoapp&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=projectkumo/kumoapp&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=projectkumo/kumoapp&type=date&legend=top-left" />
 </picture>
</a>

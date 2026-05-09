# Kumo

**A calm, native macOS client for the [Mihomo](https://github.com/MetaCubeX/mihomo) proxy core.**

Built with SwiftUI. Driven by a single control layer that's shared by the app, the CLI, and AI agents.



[Highlights](#highlights) · [Quick Start](#quick-start) · [Using Kumo](#using-kumo) · [Architecture](#architecture) · [Docs](#documentation) · [Roadmap](#roadmap)

---

## About

Kumo is a Mac utility that helps you connect quickly — not a network operations dashboard.
The first screen is designed to answer four questions and nothing else:

- Is Kumo connected?
- Which outbound mode is active?
- Is the macOS system proxy enabled?
- Which profile and proxy group are currently in use?

Power features (DNS, TUN, rule providers, connection tables, full logs) remain
discoverable behind an **Advanced** area, so daily use stays focused.

## Highlights

- **Native macOS app** — `NavigationSplitView`, `Settings`, `MenuBarExtra`, and `CommandMenu`, with standard window chrome and unified toolbar.
- **Liquid Glass, used sparingly** — only on status cards, interactive proxy chips, and primary controls. Older macOS versions get material fallbacks.
- **Agent-friendly CLI** — every command supports `--json` with a stable wrapper, dry-run for system-changing actions, and predictable exit codes.
- **One shared control layer** — `KumoCoreKit` owns the Mihomo lifecycle, profile generation, controller calls, and system proxy logic. The GUI, CLI, and future service mode all call the same facade.
- **Auto-discovery of Mihomo** — finds a core via `--core`, the `KUMO_MIHOMO_PATH` env var, a bundled binary, common Homebrew paths, or a managed install fetched from upstream.
- **Safe by default** — empty profile generates a direct config, system proxy supports `--dry-run`, and core stdout/stderr is captured to a single rotating-friendly log file.

## Screenshots

> Screenshots will land here once the v1 UI is finalized. The current layout
> is described in `[docs/macos-swiftui-interface.md](docs/macos-swiftui-interface.md)`.

## Quick Start

### Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ with the Swift 6.0 toolchain
- A Mihomo binary — Kumo can install one for you on first start, or you can point at an existing one

### Build and run

```bash
git clone https://github.com/<your-org>/kumo.git
cd kumo

# Build everything (app, CLI, library)
make swift-build

# Launch the SwiftUI app
make run-app

# Or run the CLI
make run-cli ARGS="status --json"
```

The app stores all of its state under `~/Library/Application Support/Kumo/`.
You can wipe it any time with `make reset-local-state`.

## Using Kumo

### From the macOS app

Kumo opens with **Overview** selected. Four first-level destinations cover the
full daily workflow:


| Tab          | What it's for                                                        |
| ------------ | -------------------------------------------------------------------- |
| **Overview** | Connection state, outbound mode, system proxy state, friendly errors |
| **Proxies**  | Proxy groups and node selection                                      |
| **Profiles** | Subscriptions and local profile management                           |
| **Advanced** | Lower-frequency troubleshooting and expert features                  |


Quick controls are always reachable from the menu bar (`MenuBarExtra`) and from
the keyboard:


| Action                      | Shortcut     |
| --------------------------- | ------------ |
| Start Kumo                  | ⇧⌘S          |
| Stop Kumo                   | ⌘.           |
| Rule / Global / Direct mode | ⌘1 / ⌘2 / ⌘3 |
| Refresh                     | ⌘R           |
| Settings                    | ⌘,           |


### From the command line

The `kumo` executable is a stable surface for humans, shell scripts, and coding
agents. It uses the same `KumoCoreKit` facade as the app.

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

### From an AI agent

Every command follows the same JSON envelope, so an agent can reliably script
against it:

```json
{
  "ok": true,
  "data": {},
  "error": null
}
```

Errors set `ok: false` and populate `error`. Exit code `0` means success;
exit code `1` means the command failed. Command names are intentionally close
to user goals and are committed to staying stable even if the implementation
moves to a privileged service later.

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
                │  external-controller · mixed-port · …  │
                └────────────────────────────────────────┘
```

The control layer is the contract. UI surfaces should call `KumoCoreKit`
rather than reimplementing Mihomo lifecycle, profile generation, or system
proxy logic.

### Source layout

```text
Sources/
  KumoCoreKit/   Shared domain, runtime, controller, system integration code
    Models/         Core data types (CoreStatus, ProxyGroup, Profile, …)
    Configuration/  Profile loading and runtime config generation
    Runtime/        Mihomo process supervision and managed core install
    Networking/     Mihomo external-controller HTTP client
    System/         macOS networksetup-based system proxy controller
    Support/        Paths, state storage, shared errors
  KumoCLI/       Command-line frontend for humans and agents
  KumoApp/       SwiftUI macOS frontend (Views, Stores, Liquid Glass support)
Tests/
  KumoCoreTests/ Unit tests for the shared control layer
docs/            Technical documentation (see below)
```

## Documentation

Project documentation lives under `[docs/](docs/)`:

- [Product and Information Architecture](docs/product-information-architecture.md)
- [macOS SwiftUI Interface](docs/macos-swiftui-interface.md)
- [Core Control Layer](docs/core-control-layer.md)
- [Mihomo Runtime and Controller](docs/mihomo-runtime-controller.md)
- [Profiles and Runtime Configuration](docs/profiles-runtime-configuration.md)
- [CLI and Agent Control](docs/cli-agent-control.md)
- [System Integration and Permissions](docs/system-integration-permissions.md)
- [Persistence and Logging](docs/persistence-logging.md)
- [Service Mode Roadmap](docs/service-mode-roadmap.md)
- [Testing and Quality](docs/testing-quality.md)

Agent-facing guidelines, including UI copy and SwiftUI component constraints,
live in `[AGENTS.md](AGENTS.md)`.

## Development

### Common tasks

All day-to-day commands are wrapped in `make` for convenience:

```bash
make help                   # List every available target
make swift-build            # swift build (debug)
make build-release          # swift build -c release
make run-app                # Launch the SwiftUI app
make run-cli ARGS="…"       # Run the CLI with arbitrary arguments
make cli-status             # kumo status --json
make cli-sysproxy-dry-run   # kumo sysproxy on --dry-run --json
make swift-test             # swift test
make xcode-build            # xcodebuild -scheme KumoApp
make xcode-test             # xcodebuild -scheme Kumo-Package test
make check                  # Build + test + verify CLI status output
make docs                   # List technical docs
make clean                  # swift package clean
make reset-local-state      # Remove ~/Library/Application Support/Kumo
```

### Local data

```text
~/Library/Application Support/Kumo/
  profiles/
    default.yaml
  work/
    config.yaml      # Generated Mihomo runtime config
  logs/
    core.log         # Core stdout / stderr
  state.json         # Shared state used by GUI and CLI
```

### Tests

The first test suite targets `KumoCoreKit` because that layer carries the
most important shared behavior:

- Runtime config generation
- Core state persistence
- System proxy command construction (dry-run)
- Profile repository

Tests should not mutate real system state. Use temporary application support
directories, `--dry-run` for system proxy commands, and mocked controller
responses before testing live Mihomo APIs.

```bash
swift test
# or
make xcode-test
```

## Roadmap

Kumo's first version intentionally avoids privileged helpers. The plan beyond
v1 is captured in `[docs/service-mode-roadmap.md](docs/service-mode-roadmap.md)`:

- **Service mode** — a Swift-native service for stronger lifecycle guarantees and privileged networking, with Unix socket transport and signed requests.
- **Privileged TUN setup** behind Advanced.
- **Event streams** for logs, traffic, and core lifecycle.
- **Structural YAML merge** for profile + runtime config (today's implementation appends).
- **Network service detection** for system proxy (today's default is `Wi-Fi`).
- **CLI surface growth** — `kumo logs`, `kumo doctor`, `kumo config path`, JSON schemas, shell completion.

## Contributing

Contributions are welcome. Before opening a PR, please:

1. Read `[AGENTS.md](AGENTS.md)` for the UI copy and SwiftUI component constraints.
2. Skim the document(s) under `[docs/](docs/)` that relate to your change.
3. Keep `KumoCoreKit` independent from SwiftUI — the GUI, CLI, and any future
  service must share the same domain behavior.
4. Run `make check` (or `swift test`) and verify `kumo status --json` still
  returns valid JSON.
5. If your change meaningfully alters product behavior, architecture, runtime
  configuration, persistence, permissions, testing expectations, or UI  
   information architecture, update the matching document under `docs/` in the  
   same change set.

## Acknowledgements

- [Mihomo](https://github.com/MetaCubeX/mihomo) — the proxy core that Kumo drives.
- The Clash / Mihomo ecosystem — for the controller API conventions Kumo speaks.
- Apple — for SwiftUI, Liquid Glass, and the macOS HIG.


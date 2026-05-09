# Kumo Technical Documentation

Kumo is a native macOS client for Mihomo. The first version focuses on a calm daily-use interface, a shared control layer, and an agent-friendly CLI. Advanced networking features remain discoverable, but they are not placed in the primary workflow.

## Document Map

- [Product and Information Architecture](product-information-architecture.md)
- [macOS SwiftUI Interface](macos-swiftui-interface.md)
- [Core Control Layer](core-control-layer.md)
- [Mihomo Runtime and Controller](mihomo-runtime-controller.md)
- [Profiles and Runtime Configuration](profiles-runtime-configuration.md)
- [CLI and Agent Control](cli-agent-control.md)
- [System Integration and Permissions](system-integration-permissions.md)
- [Persistence and Logging](persistence-logging.md)
- [Service Mode Roadmap](service-mode-roadmap.md)
- [Testing and Quality](testing-quality.md)

## Current Source Layout

```text
Sources/
  KumoCoreKit/   Shared domain, runtime, controller, system integration code
  KumoCLI/       Command-line frontend for humans and agents
  KumoApp/       SwiftUI macOS frontend
Tests/
  KumoCoreTests/ Unit tests for the shared control layer
```

## Architectural Principle

The GUI, CLI, and future service mode must share the same domain behavior. UI surfaces should call `KumoCoreKit` rather than reimplementing Mihomo lifecycle, profile generation, or system proxy logic.

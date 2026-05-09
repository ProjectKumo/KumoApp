# Core Control Layer

## Purpose

`KumoCoreKit` is the shared domain layer for the GUI, CLI, tests, and future service mode. It prevents the app from developing separate, inconsistent implementations for lifecycle control, profile generation, controller calls, and system proxy changes.

## Public Entry Point

`KumoController` is the high-level facade. It currently exposes:

- `status()`
- `start(corePath:)`
- `stop()`
- `restart(corePath:)`
- `setMode(_:)`
- `proxyGroups()`
- `selectProxy(group:name:)`
- `refreshProfile(from:)`
- `setSystemProxy(_:dryRun:)`

This API is intentionally close to the CLI command vocabulary and the future service API.

## Internal Responsibilities

`KumoCoreKit` is split by responsibility:

- Models: `Profile`, `ProxyGroup`, `ProxyNode`, `CoreStatus`, `OutboundMode`.
- Configuration: profile loading and runtime config generation.
- Runtime: Mihomo process supervision.
- Networking: Mihomo external-controller client.
- System: macOS system proxy command construction and execution.
- Support: paths, state storage, and shared errors.

## Design Rules

- Keep UI concerns out of `KumoCoreKit`.
- Keep `Process` and shell execution behind small wrappers.
- Keep dry-run paths available for tests and agent workflows.
- Keep error messages specific enough for UI and CLI display.

## Future Compatibility

When a privileged service is introduced, `KumoController` should be able to switch from local implementations to service-backed implementations without changing GUI or CLI command semantics.

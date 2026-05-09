# Product and Information Architecture

## Goal

Kumo should feel like a Mac utility that helps users connect quickly, not like a network operations dashboard. The first screen must answer four questions:

- Is Kumo connected?
- Which outbound mode is active?
- Is the macOS system proxy enabled?
- Which profile and proxy group are currently in use?

## Primary Navigation

The main app uses four first-level destinations:

- **Overview**: connection state, outbound mode, system proxy state, and friendly errors.
- **Proxies**: proxy groups and node selection.
- **Profiles**: subscription and local profile management.
- **Advanced**: lower-frequency troubleshooting and expert features.

This keeps daily operations in the first two screens while preserving access to deeper capabilities.

## Advanced Area

The following features belong behind `Advanced` or `Settings`:

- DNS control
- TUN configuration
- Rule provider inspection
- Connection tables
- Full logs
- Service mode setup
- Core path overrides
- Future Subconverter-style transformations

These features are important, but they should not compete with the core daily workflow.

## Empty and Error States

Kumo should use plain-language messages:

- Missing core: explain how to provide a Mihomo binary path.
- No profile: explain where to add a default profile or how to use the CLI refresh command.
- Controller unavailable: explain that the core may not be running yet.
- System proxy failure: show the failed command and suggest checking network service names.

The user should always know what happened and what to try next.

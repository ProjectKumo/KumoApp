# Product and Information Architecture

## Goal

Kumo should feel like a Mac utility that helps users connect quickly, not like a network operations dashboard. The first screen must answer four questions:

- Is Kumo connected?
- Which outbound mode is active?
- Is the macOS system proxy enabled?
- Which profile and proxy group are currently in use?

## Primary Navigation

The main app uses a source-list sidebar grouped by task frequency:

- **Daily**: Overview, Profiles, Proxies.
- **Inspect**: Connections, Logs, Rules.
- **Configure**: Core, System Proxy, DNS, TUN, Sniffer, Resources, Overrides, Sub-Store.

This keeps daily operations at the top while preserving access to deeper capabilities without hiding them behind a generic advanced page.

## Configure Area

The following features belong in `Configure` or `Settings`:

- DNS control
- TUN configuration
- Sniffer configuration
- Service mode setup
- Core path overrides
- External resources and provider management
- Ordered YAML overrides and future JavaScript transforms
- Future Sub-Store integration

Inspect-only features such as connection tables, full logs, and rules live in `Inspect`, because they answer what the core is doing rather than how it should be configured.

## Empty and Error States

Kumo should use plain-language messages:

- Missing core: explain how to provide a Mihomo binary path.
- No profile: explain where to add a default profile or how to use the CLI refresh command.
- Controller unavailable: explain that the core may not be running yet.
- System proxy failure: show the failed command and suggest checking network service names.
- Provider or override failure: identify the resource, action, and whether the running core needs a refresh or restart.

The user should always know what happened and what to try next.

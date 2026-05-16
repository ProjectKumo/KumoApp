# ADR-003: Storing Hosts in DnsSettings but Emitting as Top-Level YAML

## Status

Accepted

## Context

Mihomo's configuration structure has `hosts` as a top-level key, parallel to `dns` and `sniffer`:

```yaml
dns:
  enable: true
  nameserver:
    - https://doh.pub/dns-query
hosts:
  localhost: 127.0.0.1
  example.com: 1.2.3.4
```

However, from a user workflow perspective, hosts editing belongs alongside DNS configuration. Users who configure DNS typically also want to manage custom hosts entries. Sparkle places the hosts editor in the same configuration panel as DNS settings.

The question was: should Kumo store `hosts` as a standalone model (top-level struct), or nested within `DnsSettings`?

## Decision

Store `hosts` inside `DnsSettings` for UI and persistence convenience, but emit it as a top-level YAML block during runtime config generation.

### Rationale

1. **UI cohesion**: The DNS configuration view in KumoApp includes a "Hosts" section. Users edit hosts in the same context as DNS settings. Keeping `hosts` in `DnsSettings` avoids an extra model, store method, and view state.

2. **Persistence simplicity**: `hosts` travels with `DnsSettings` through `CoreStatus.runtimeSettings` → `CoreStateStore` → JSON. No separate persistence path needed.

3. **YAML correctness**: `RuntimeConfigBuilder.controlledHostsYAML()` emits `hosts:` as an independent top-level block, matching Mihomo's expected structure.

4. **Controlled key handling**: `hosts` is only added to `controlledTopLevelKeys` when the user has configured hosts (`!dns.hosts.isEmpty`). If the user hasn't configured hosts, profile-provided `hosts` entries are preserved.

### Implementation Details

- `DnsSettings.hosts: [String: PolicyValue]` — storage field
- `RuntimeConfigBuilder.controlledHostsYAML(_:)` — generates top-level `hosts:` block
- `MihomoControllerClient` parses top-level `hosts` from controller response and merges into `DnsSettings.hosts`
- `KumoCoreKit.runtimePatch()` emits `hosts` as a separate top-level key (not nested under `dns`)

## Consequences

### Positive

- Users manage DNS and hosts in one place.
- Single persistence and state management path.
- YAML output is correct for Mihomo.
- Profile hosts are preserved when the user hasn't configured UI hosts.

### Negative

- Semantic mismatch: `hosts` is not logically a sub-field of DNS, but it's stored that way.
- Controller parsing requires a merge step: read `hosts` from top-level response, merge into `DnsSettings`.
- Runtime PATCH must extract `hosts` from `DnsSettings` and place it at the top level.
- Future maintainers may be confused why `hosts` is in `DnsSettings` when Mihomo has it at the top level.

### Mitigations

- Documented in `docs/core/dns-and-sniffer-configuration.md` and this ADR.
- Clear naming: `DnsSettings.hosts` acknowledges the storage location, while `controlledHostsYAML` and `runtimePatch` handle the emission correctly.

## Alternatives Considered

### Alternative: Standalone `HostsSettings` Model

Create a separate `HostsSettings` struct with its own UI section, store methods, and persistence. Rejected because it adds significant boilerplate for a single `[String: PolicyValue]` field and complicates the Configure navigation.

### Alternative: Always Strip Profile Hosts

Always add `hosts` to `controlledTopLevelKeys` regardless of whether the user has configured UI hosts. Rejected because it would silently drop profile-provided hosts entries, breaking user expectations.

## Related

- `docs/core/dns-and-sniffer-configuration.md`
- `Sources/KumoCoreKit/Configuration/RuntimeConfigBuilder.swift`
- `Sources/KumoCoreKit/Networking/MihomoControllerClient.swift`

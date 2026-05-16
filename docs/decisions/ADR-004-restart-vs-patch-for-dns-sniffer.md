# ADR-004: Core Restart for DNS/Sniffer Changes Instead of Runtime PATCH

## Status

Accepted

## Context

When a user applies DNS or Sniffer settings through the Kumo UI, there are two ways to propagate the changes to the running Mihomo core:

1. **PATCH `/configs`**: Send the new configuration as a JSON patch to Mihomo's external-controller API. The core updates its running config without restarting.
2. **Restart the core**: Write the new runtime YAML and restart the Mihomo process.

Mihomo's `/configs` PATCH endpoint supports updating many fields, but its behavior for structural changes (especially `dns` and `sniffer` blocks) is not well-documented and may have edge cases.

## Decision

Apply DNS and Sniffer changes by **restarting the core**, not by PATCHing `/configs`.

### Rationale

1. **Structural config changes**: DNS and Sniffer configuration includes nested structures (`sniff.HTTP.ports`, `fallback-filter.geoip-code`, `nameserver-policy` with mixed types). Mihomo's PATCH behavior for nested structural changes is undefined and may not fully apply.

2. **Consistency with TUN**: TUN changes already restart the core because Mihomo expects interface-level changes to be loaded from the generated runtime YAML. DNS and Sniffer follow the same pattern for consistency.

3. **Deterministic state**: After a restart, the core's running config exactly matches the generated `config.yaml`. With PATCH, there's a risk of divergence between the generated file and the running state.

4. **Sparkle behavior**: Sparkle also restarts the core when applying DNS/TUN/Sniffer settings, suggesting this is the expected Mihomo workflow.

### Implementation

```swift
public func applyDnsSettings(_ settings: DnsSettings) async throws -> DnsSettings {
    let normalized = normalizedDnsSettings(settings)
    var status = try stateStore.load()
    status.runtimeSettings.dns = normalized
    try stateStore.save(status)
    let result = try restart()
    try await waitForControllerReady()
    return normalized
}
```

The same pattern applies to `applySnifferSettings(_:)` and `applyTunSettings(_:)`.

### Exception: Runtime Settings PATCH

`updateRuntimeSettings(_:)` (called from CoreView for mixed-port, log-level, mode, etc.) still uses PATCH because those are simple scalar changes that Mihomo handles reliably. The `runtimePatch(for:)` method builds a patch dictionary that includes `dns` and `sniffer` keys when enabled, plus `hosts` as a top-level key.

## Consequences

### Positive

- Deterministic configuration state.
- Avoids Mihomo PATCH edge cases for nested structures.
- Consistent with TUN application pattern.
- Matches Sparkle behavior.

### Negative

- User experiences a brief connection interruption during restart.
- Slightly slower than PATCH (restart + controller ready wait).
- More system load (process stop/start instead of in-memory update).

### Mitigations

- `waitForControllerReady()` minimizes the downtime window (~1-3 seconds).
- The UI shows a loading state during restart.
- Simple scalar changes (mode, mixed-port) still use PATCH for instant feedback.

## Related

- `docs/core/mihomo-runtime-controller.md`
- `Sources/KumoCoreKit/KumoCoreKit.swift` (`applyDnsSettings`, `applySnifferSettings`)

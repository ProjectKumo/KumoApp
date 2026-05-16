# ADR-001: DNS and Sniffer Decoupled from TUN

## Status

Accepted

## Context

Originally, Kumo managed DNS settings as part of TUN configuration. `TunSettings` contained DNS-related fields (`dnsEnabled`, `dnsEnhancedMode`, `fakeIPRange`, `nameservers`), and `RuntimeConfigBuilder` emitted DNS YAML only when TUN was enabled. This mirrored an early design where DNS interception was primarily a TUN feature.

However, Mihomo supports DNS and Sniffer as fully independent top-level configuration domains:
- DNS can be enabled without TUN (e.g., for system proxy + fake-ip mode)
- Sniffer can be enabled without TUN or DNS (e.g., for protocol detection on mixed-port traffic)
- Sparkle (the reference product) exposes DNS and Sniffer as independent configuration panels

## Decision

Decouple DNS and Sniffer from TUN into independent runtime domains:

1. **Remove DNS fields from `TunSettings`**: Delete `dnsEnabled`, `dnsEnhancedMode`, `fakeIPRange`, and `nameservers` from `TunSettings`.
2. **Create `DnsSettings` and `SnifferSettings`**: Full-featured models aligned with Mihomo's configuration surface and Sparkle's UI.
3. **Add to `CoreRuntimeSettings`**: `CoreRuntimeSettings` gains `dns: DnsSettings?` and `sniffer: SnifferSettings?` properties.
4. **Independent YAML generation**: `RuntimeConfigBuilder` emits `dns`, `sniffer`, and `hosts` blocks independently, controlled by their own enable flags rather than TUN state.
5. **Independent UI views**: `DNSView` and `SnifferView` are separate Configure pages with their own staged draft + Reset/Apply patterns.
6. **No legacy fallback**: Do not maintain backward-compatibility shims for the old TUN-embedded DNS fields. Old state storage will silently ignore the removed keys during Codable decoding.

## Consequences

### Positive

- Full parity with Sparkle's DNS/Sniffer feature surface.
- Users can enable DNS or Sniffer without enabling TUN.
- Domain boundaries are clear: TUN = virtual interface, DNS = name resolution, Sniffer = protocol detection.
- Independent enable/disable toggles in the UI.

### Negative

- State migration: users upgrading from versions with TUN-embedded DNS will lose their DNS settings and need to reconfigure them in the new DNS view.
- More controlled top-level keys to manage in `RuntimeConfigBuilder`.
- Three separate restart paths (TUN, DNS, Sniffer) instead of one combined restart.

## Related

- `docs/core/dns-and-sniffer-configuration.md`
- `docs/roadmap/sparkle-parity-roadmap.md`

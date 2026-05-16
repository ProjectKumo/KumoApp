# DNS and Sniffer Configuration

## Overview

DNS and Sniffer are independent runtime domains in Kumo, decoupled from TUN as of the DNS/Sniffer parity pass. Each domain has its own settings model, YAML generation path, controller parsing path, and UI view. They are controlled separately: enabling DNS does not require TUN, and enabling Sniffer does not require either.

## Architecture

```
KumoApp (SwiftUI)
  ├── DNSView ──────→ KumoAppStore.applyDnsSettings()
  │                      └── KumoController.applyDnsSettings()
  │                           ├── stateStore.save()
  │                           └── restart() → RuntimeConfigBuilder
  │
  └── SnifferView ──→ KumoAppStore.applySnifferSettings()
                           └── KumoController.applySnifferSettings()
                                ├── stateStore.save()
                                └── restart() → RuntimeConfigBuilder
```

The key design decision is that **DNS/Sniffer changes restart the core** rather than being PATCHed at runtime. This matches Mihomo's expectation that structural configuration changes are loaded from the generated runtime YAML, not from piecemeal API patches.

## Models

### DnsSettings

Stored in `CoreRuntimeSettings.dns`, persisted as part of `CoreStatus.runtimeSettings`.

| Field | Type | Default | YAML Key |
|-------|------|---------|----------|
| `isEnabled` | `Bool` | `true` | `dns.enable` |
| `listen` | `String` | `""` | `dns.listen` |
| `ipv6` | `Bool` | `false` | `dns.ipv6` |
| `ipv6Timeout` | `Int` | `100` | `dns.ipv6-timeout` |
| `preferH3` | `Bool` | `false` | `dns.prefer-h3` |
| `enhancedMode` | `String` | `"fake-ip"` | `dns.enhanced-mode` |
| `fakeIPRange` | `String` | `"198.18.0.1/16"` | `dns.fake-ip-range` |
| `fakeIPRange6` | `String` | `""` | `dns.fake-ip-range6` |
| `fakeIPFilter` | `[String]` | `[]` | `dns.fake-ip-filter` |
| `fakeIPFilterMode` | `String` | `""` | `dns.fake-ip-filter-mode` |
| `useHosts` | `Bool` | `false` | `dns.use-hosts` |
| `useSystemHosts` | `Bool` | `false` | `dns.use-system-hosts` |
| `respectRules` | `Bool` | `false` | `dns.respect-rules` |
| `defaultNameserver` | `[String]` | `[]` | `dns.default-nameserver` |
| `nameserver` | `[String]` | `[]` | `dns.nameserver` |
| `fallback` | `[String]` | `[]` | `dns.fallback` |
| `fallbackFilter` | `[String: FallbackFilterValue]` | `[:]` | `dns.fallback-filter` |
| `proxyServerNameserver` | `[String]` | `[]` | `dns.proxy-server-nameserver` |
| `directNameserver` | `[String]` | `[]` | `dns.direct-nameserver` |
| `directNameserverFollowPolicy` | `Bool` | `false` | `dns.direct-nameserver-follow-policy` |
| `nameserverPolicy` | `[String: PolicyValue]` | `[:]` | `dns.nameserver-policy` |
| `proxyServerNameserverPolicy` | `[String: PolicyValue]` | `[:]` | `dns.proxy-server-nameserver-policy` |
| `cacheAlgorithm` | `String` | `""` | `dns.cache-algorithm` |
| `hosts` | `[String: PolicyValue]` | `[:]` | `hosts` (top-level) |

### SnifferSettings

Stored in `CoreRuntimeSettings.sniffer`, persisted as part of `CoreStatus.runtimeSettings`.

| Field | Type | Default | YAML Key |
|-------|------|---------|----------|
| `isEnabled` | `Bool` | `true` | `sniffer.enable` |
| `parsePureIP` | `Bool` | `true` | `sniffer.parse-pure-ip` |
| `forceDNSMapping` | `Bool` | `true` | `sniffer.force-dns-mapping` |
| `overrideDestination` | `Bool` | `false` | `sniffer.override-destination` |
| `httpOverrideDestination` | `Bool` | `false` | `sniffer.sniff.HTTP.override-destination` |
| `httpPorts` | `[Int]` | `[80, 8080]` | `sniffer.sniff.HTTP.ports` |
| `tlsPorts` | `[Int]` | `[443, 8443]` | `sniffer.sniff.TLS.ports` |
| `quicPorts` | `[Int]` | `[]` | `sniffer.sniff.QUIC.ports` |
| `skipDomain` | `[String]` | `[]` | `sniffer.skip-domain` |
| `forceDomain` | `[String]` | `[]` | `sniffer.force-domain` |
| `skipDstAddress` | `[String]` | `["91.108.4.0/22", "91.108.8.0/22", ...]` | `sniffer.skip-dst-address` |
| `skipSrcAddress` | `[String]` | `[]` | `sniffer.skip-src-address` |

## Mixed-Type Policy Values

Mihomo allows several fields to be either a single string or an array of strings. Kumo represents this with `PolicyValue`:

```swift
public enum PolicyValue: Codable, Equatable, Sendable {
    case single(String)
    case multiple([String])
}
```

Fields using `PolicyValue`:
- `DnsSettings.nameserverPolicy`
- `DnsSettings.proxyServerNameserverPolicy`
- `DnsSettings.hosts`

### FallbackFilterValue

`dns.fallback-filter` has a more complex type: `{ [key: string]: boolean | string | string[] }`. Kumo uses a separate enum:

```swift
public enum FallbackFilterValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case single(String)
    case multiple([String])
}
```

This is intentionally separate from `PolicyValue` because the boolean case (`geoip: true`) cannot be represented by `PolicyValue`, and mixing the two would create an overly broad type.

## YAML Generation

### Controlled Keys

`RuntimeConfigBuilder` maintains a set of controlled top-level keys that are stripped from user profiles and replaced with Kumo-managed values:

```swift
private static let controlledTopLevelKeys: Set<String> = [
    "external-controller", "secret", "mixed-port", "mode",
    "allow-lan", "log-level", "ipv6", "find-process-mode",
    "geodata-mode", "geo-auto-update", "geo-update-interval",
    "geox-url", "dns", "sniffer"
]
```

Dynamic additions:
- `tun` — when `runtimeSettings.tun?.isEnabled == true`
- `dns` — when `runtimeSettings.dns?.isEnabled == true`
- `sniffer` — when `runtimeSettings.sniffer?.isEnabled == true`
- `hosts` — when `runtimeSettings.dns?.hosts.isEmpty == false`

### Hosts Top-Level Emission

`hosts` is special: it is stored inside `DnsSettings` for UI convenience, but emitted as a top-level YAML block because Mihomo expects `hosts` at the root level of the config:

```yaml
# Kumo controlled hosts
hosts:
  localhost: "127.0.0.1"
  example.com: "1.2.3.4"
```

The `hosts` key is only added to `controlledTopLevelKeys` when the user has configured hosts. If the user has not configured hosts, profile-provided `hosts` entries are preserved. This avoids silently dropping user data.

### Empty Value Omission

Most fields are omitted from YAML when empty/default:
- Empty strings (`listen`, `fakeIPRange6`, `fakeIPFilterMode`, `cacheAlgorithm`)
- Empty arrays (`fakeIPFilter`, `defaultNameserver`, `nameserver`, etc.)
- Empty dictionaries (`fallbackFilter`, `nameserverPolicy`, `hosts`)

Exceptions (always emitted):
- `dns.enable`, `dns.ipv6`, `dns.use-hosts`, `dns.use-system-hosts`, `dns.respect-rules`
- `sniffer.enable`, `sniffer.parse-pure-ip`, `sniffer.force-dns-mapping`, `sniffer.override-destination`

## Controller Parsing

### From Mihomo /configs

`MihomoControllerClient.configuration()` fetches the full config and parses it into `CoreConfigurationSnapshot`.

**Hosts parsing**: Because `hosts` is a top-level key in Mihomo's config but stored in `DnsSettings` in Kumo, the parser reads `hosts` from the top-level object and merges it into the parsed `DnsSettings`:

```swift
let topLevelHosts = policyValueDict(from: object["hosts"])
var parsedDNS = dnsSettings(from: dns)  // parses from object["dns"]
if parsedDNS == nil, !topLevelHosts.isEmpty {
    parsedDNS = DnsSettings(isEnabled: false)
}
parsedDNS?.hosts = topLevelHosts
```

This handles the edge case where Mihomo has `hosts` configured but no `dns` block.

### PolicyValue Parsing

`policyValueDict(from:)` handles the mixed-type values:
- If the value is a `String`, wraps it in `.single`
- If the value is an array of strings, wraps it in `.multiple`
- Otherwise, ignores the entry

### FallbackFilterValue Parsing

`fallbackFilterDict(from:)` uses heuristic parsing:
- `Bool` → `.bool`
- `String` → `.single`
- `[String]` → `.multiple`
- Other types are ignored

## Runtime Patch (Live Core)

When `updateRuntimeSettings()` is called while the core is running, a PATCH is sent to `/configs`. The patch includes:

- `dns` — all enabled DNS fields (but NOT `hosts`, see below)
- `sniffer` — all enabled Sniffer fields
- `hosts` — as a separate top-level key, extracted from `DnsSettings.hosts`

This separation is necessary because Mihomo's `/configs` PATCH expects `hosts` at the top level, not nested under `dns`.

## UI Patterns

### Staged Draft with Reset/Apply

Both `DNSView` and `SnifferView` follow the same pattern established by `TunView`:

1. On appear: copy current settings into local `@State` draft
2. User edits draft (not committed to store)
3. "Reset" button restores draft from store
4. "Apply" button validates, normalizes, and commits to store
5. Store calls `controller.applyDnsSettings()` which saves state and restarts core

This prevents partial/inconsistent states from reaching the running core.

### Validation

`DNSValidator` provides validation helpers:
- `isValidListenAddress(_:)` — checks `host:port` format
- `isValidFakeIPFilterMode(_:)` — checks `whitelist` or `blacklist`
- `isValidCacheAlgorithm(_:)` — checks `lru` or `arc`

Validation runs on Apply, not on every keystroke.

## Files by Responsibility

| File | Responsibility |
|------|---------------|
| `Models/Models.swift` | `DnsSettings`, `SnifferSettings`, `PolicyValue`, `FallbackFilterValue` definitions |
| `Configuration/RuntimeConfigBuilder.swift` | YAML generation for `dns`, `sniffer`, and `hosts` blocks |
| `Networking/MihomoControllerClient.swift` | Parsing `dns` and `hosts` from controller responses |
| `KumoCoreKit.swift` | `dnsPatch(for:)`, `snifferPatch(for:)`, `normalizedDnsSettings()`, `normalizedSnifferSettings()` |
| `Support/DNSValidator.swift` | Validation helpers for DNS fields |
| `Views/ConfigureViews.swift` | `DNSView`, `SnifferView`, and shared UI components |
| `Stores/KumoAppStore.swift` | `applyDnsSettings()`, `applySnifferSettings()`, `setDnsEnabled()`, `setSnifferEnabled()` |

## Future Work

- Extract DNS/Sniffer logic from `KumoCoreKit.swift` into dedicated domain coordinators.
- Add structured tests for `PolicyValue` and `FallbackFilterValue` Codable round-trips.
- Consider moving `hosts` out of `DnsSettings` into a standalone model if the semantic coupling becomes confusing.

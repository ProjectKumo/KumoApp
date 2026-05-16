# ADR-002: PolicyValue and FallbackFilterValue Enums for Mixed-Type Fields

## Status

Accepted

## Context

Mihomo's configuration allows several fields to hold either a single value or an array of values:

- `nameserver-policy: { "geosite:cn": "223.5.5.5" }` — single string
- `nameserver-policy: { "geosite:cn": ["223.5.5.5", "119.29.29.29"] }` — array of strings
- `hosts: { "localhost": "127.0.0.1" }` — single string
- `hosts: { "example.com": ["1.2.3.4", "5.6.7.8"] }` — array of strings

Additionally, `fallback-filter` has an even more complex type:
- `fallback-filter: { "geoip": true }` — boolean
- `fallback-filter: { "geoip-code": "CN" }` — single string
- `fallback-filter: { "ipcidr": ["100.100.100.100/32"] }` — array of strings

Using `[String: Any]` or `[String: String]` for these fields is either type-unsafe or too restrictive.

## Decision

1. **Create `PolicyValue` enum** for `String | [String]` fields:
   ```swift
   public enum PolicyValue: Codable, Equatable, Sendable {
       case single(String)
       case multiple([String])
   }
   ```
   Used by: `nameserverPolicy`, `proxyServerNameserverPolicy`, `hosts`.

2. **Create `FallbackFilterValue` enum** for `Bool | String | [String]` fields:
   ```swift
   public enum FallbackFilterValue: Codable, Equatable, Sendable {
       case bool(Bool)
       case single(String)
       case multiple([String])
   }
   ```
   Used by: `fallbackFilter`.

3. **Custom Codable implementations** for both enums to handle the mixed-type JSON/YAML serialization.

4. **Do not unify into a single enum**: `FallbackFilterValue` is intentionally separate from `PolicyValue` because the boolean case (`geoip: true`) has no equivalent in `PolicyValue`. Attempting to merge them would create an overly broad type that allows invalid states (e.g., `fallback-filter: { "geoip": "CN" }`).

## Consequences

### Positive

- Type-safe representation of Mihomo's mixed-type fields.
- Swift compiler enforces valid state at compile time.
- Clean YAML/JSON serialization through custom Codable.
- UI can pattern-match on `.single`/`.multiple` to render appropriate editors.

### Negative

- Two similar enums create mild code duplication in Codable conformance.
- Controller parsing and patch building must handle three cases instead of one.
- UI text editors need heuristic parsing to reconstruct the enum from user input.

## Related

- `docs/core/dns-and-sniffer-configuration.md`
- `Sources/KumoCoreKit/Models/Models.swift` (PolicyValue and FallbackFilterValue definitions)

# Profiles and Runtime Configuration

## Profile Sources

Kumo models profiles with `ProfileSource`:

- `remote(URL)` for subscription URLs.
- `file(URL)` for local Clash or Mihomo YAML files.
- `inline` for generated fallback profiles.

The first version supports a default local profile and remote refresh through the CLI.

## Default Profile

If no default profile exists, `ProfileRepository` returns a minimal direct profile:

```yaml
proxies: []
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DIRECT
```

This lets the app start with a safe empty state instead of crashing on missing configuration.

## Runtime Config Generation

`RuntimeConfigBuilder` appends Kumo-controlled runtime settings to the selected profile:

- `external-controller`
- `secret`
- `mixed-port`
- `mode`
- `allow-lan`
- `log-level`
- `ipv6`
- Geo data settings

The goal is to keep user profiles portable while ensuring Kumo can control the running core.

## Overrides

Kumo plans an ordered override layer:

1. Selected profile YAML.
2. Profile-specific overrides.
3. Global overrides.
4. Kumo-controlled runtime settings.

The final layer always wins for controller address, ports, mode, and other Kumo-owned keys.

## Current Merge Strategy

The current implementation merges YAML at top-level block granularity:

1. The selected profile provides the base document.
2. Later overrides replace earlier blocks with the same top-level key.
3. Kumo-owned runtime keys are removed from user-provided documents.
4. Kumo-controlled runtime settings are appended last and always win.

This gives deterministic precedence for common Mihomo configuration sections
without introducing JavaScript transforms or a privileged service dependency.
Future work should move from top-level block merging to a full YAML AST so
comments, anchors, nested map merges, and formatting can be preserved more
precisely.

## Future Work

- Add full YAML AST parsing.
- Preserve comments where possible.
- Track subscription user info from response headers.
- Add profile metadata and multiple profile selection.
- Add advanced YAML override files.
- Add JavaScript transforms only after the YAML override flow and sandbox strategy are stable.
- Add Sub-Store integration after runtime configuration and resource management are stable.

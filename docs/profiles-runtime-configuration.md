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

The goal is to keep user profiles portable while ensuring Kumo can control the running core.

## Current Merge Strategy

The current implementation appends controlled YAML. This is a first step. A production merge should parse YAML structurally and replace controlled keys with deterministic precedence.

## Future Work

- Add structural YAML parsing.
- Preserve comments where possible.
- Track subscription user info from response headers.
- Add profile metadata and multiple profile selection.
- Add advanced YAML override files.
- Delay JavaScript and full Subconverter-style transformations until the core app is stable.

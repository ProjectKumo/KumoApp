# Agent Path Index

Quick reference for AI agents working on this codebase. Each entry maps a
task category to the canonical document or command that owns it.

## Release

**SOP:** [docs/operations/release-management.md](operations/release-management.md)

Key commands:

```bash
# Full workflow: pull → build arm64 → build amd64 → tag → release → upload manifests
make clean
make release-dmg VERSION=0.0.10       # arm64
rm -rf build/Build/Products/Release build/release/latest.yml
make release-dmg-amd64 VERSION=0.0.10  # amd64

git tag -a "0.0.10" -m "Kumo 0.0.10"
git push origin "0.0.10"

gh release create "0.0.10" --title "Kumo 0.0.10" --notes "..." \
  build/release/Kumo-macos-0.0.10-arm64.dmg \
  build/release/Kumo-macos-0.0.10-amd64.dmg

gh release upload "0.0.10" \
  build/release/latest.yml \
  build/release/latest-amd64.yml \
  --clobber
```

**Never forget:** upload `latest.yml` + `latest-amd64.yml` after creating the
release. The in-app update checker will 404 without them.

**Verify URLs:**

```bash
curl -sI "https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest.yml"
curl -sI "https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest-amd64.yml"
```

## Update Runtime Behavior

**Docs:** [docs/operations/app-updates/README.md](operations/app-updates/README.md)

- Feed URLs, manifest contract, polling logic, notifications, installer helper.
- `AppUpdateManager` in `Sources/KumoCoreKit/Support/AppUpdateManager.swift`.
- Architecture-aware feed suffix: arm64 → `latest.yml`, x86_64 → `latest-amd64.yml`.

## Domain Reference

| Area | Document |
|------|----------|
| Product scope | [product/README.md](product/README.md) |
| UI surfaces (SwiftUI, CLI, agent control) | [interfaces/README.md](interfaces/README.md) |
| Control layer, Mihomo runtime, profiles | [core/README.md](core/README.md) |
| App packaging, permissions, persistence, logging, releases | [operations/README.md](operations/README.md) |
| Testing strategy | [quality/README.md](quality/README.md) |
| Service-mode direction, Sparkle parity | [roadmap/README.md](roadmap/README.md) |
| Cross-domain implementation standards | [standards/README.md](standards/README.md) |

## Source Layout

```
Sources/
  KumoCoreKit/   Shared domain, runtime, controller, system integration
  KumoCLI/       Command-line frontend
  KumoApp/       SwiftUI macOS frontend
Tests/
  KumoCoreTests/ Unit tests for the shared control layer
```

## Common Commands

```bash
make app              # Debug build
make dev              # Quit, clean debug, build, and open
make test             # Run unit tests
make clean            # Remove all build artifacts
make release-dmg VERSION=x.y.z          # arm64 release
make release-dmg-amd64 VERSION=x.y.z    # amd64 release
```

## Decision Records

ADRs live in [decisions/](decisions/):

- [ADR-001](decisions/ADR-001-dns-sniffer-decoupling.md) — DNS/Sniffer decoupling
- [ADR-002](decisions/ADR-002-policy-value-types.md) — Policy value types
- [ADR-003](decisions/ADR-003-hosts-top-level-vs-nested.md) — Hosts top-level vs nested
- [ADR-004](decisions/ADR-004-restart-vs-patch-for-dns-sniffer.md) — Restart vs patch for DNS/Sniffer

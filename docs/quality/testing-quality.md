# Testing and Quality

## Current Tests

The first test suite covers:

- Runtime config generation.
- Core state persistence.
- System proxy command construction in dry-run mode.
- Mihomo controller response mapping with mocked URL loading.
- Backup export/import round trips.
- Service request signing.
- CLI argument parsing, JSON envelope stability, color/log rendering rules, and
  npm-style help behavior.

These tests target `KumoCoreKit` because that layer carries the most important shared behavior.

## Verification Commands

Use:

```bash
swift build --product kumo
swift test
.build/debug/kumo --help
.build/debug/kumo status --json
.build/debug/kumo skills install --agent codex --scope global --dry-run --json
```

Do not start a development server. This project is a Swift package, not a web app.
For user-facing release checks, prefer the bundled helper at
`Kumo.app/Contents/Helpers/kumo` and the `/usr/local/bin/kumo` symlink over
`swift run kumo`.

## Test Strategy

Prioritize tests that do not mutate real system state:

- Use temporary application support directories.
- Use dry-run for system proxy commands.
- Mock controller responses before testing live Mihomo APIs.
- Avoid tests that require a real network subscription.

## Areas That Need More Coverage

- Profile import and remote refresh errors.
- Missing core path errors.
- UI store behavior.
- Future Unix socket transport.
- Exact system proxy restore from snapshots.
- App update manifest and checksum flows.

## Quality Rules

- Keep `KumoCoreKit` independent from SwiftUI.
- Keep command execution isolated.
- Use explicit errors instead of generic failures.
- Keep advanced features behind advanced UI.
- Prefer small files grouped by domain responsibility.

## Manual QA Checklist

- `kumo status --json` returns valid JSON.
- `kumo --help`, `kumo -l`, `kumo help json`, and `kumo completion zsh` return
  npm-style discoverability output.
- `kumo status --color never` contains no ANSI escapes, and `kumo status --json`
  remains plain JSON even when `--color always` is supplied.
- `kumo status --silent` succeeds without successful text output.
- `kumo doctor --timing` writes timing diagnostics without polluting JSON output.
- `kumo logs cli --limit 5` and `kumo logs clean --dry-run --json` operate on
  CLI debug logs without touching runtime logs.
- Missing Mihomo core shows a clear error.
- Empty profile still generates a safe direct config.
- System proxy dry-run prints the expected commands.
- SwiftUI window opens with Overview selected.
- Settings opens with Cmd+,.
- Inspect search fields remain available when a query returns no matches.
- Core runtime and System Proxy settings only commit after the user applies staged edits.
- TUN helper uninstall asks for confirmation before removing the service.
- Menu bar status item exposes start, stop, mode switching, refresh, profiles, proxy groups, and system proxy controls.
- App updates check the default GitHub Releases feed when no manifest override is set.
- App update DMG downloads fail closed on SHA-256 mismatch and report a clear error when the current app location is not writable.
- `kumo doctor --json` reports status, profile, and core candidate information.
- `kumo backup export <path> --json` creates a manifest-backed backup directory.
- `kumo substore status --json` reports enabled state, frontend/backend runtime
  state, resource version, and local URL without launching a dev server.

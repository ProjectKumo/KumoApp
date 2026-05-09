# Testing and Quality

## Current Tests

The first test suite covers:

- Runtime config generation.
- Core state persistence.
- System proxy command construction in dry-run mode.

These tests target `KumoCoreKit` because that layer carries the most important shared behavior.

## Verification Commands

Use:

```bash
swift build
swift test
swift run kumo status --json
```

Do not start a development server. This project is a Swift package, not a web app.

## Test Strategy

Prioritize tests that do not mutate real system state:

- Use temporary application support directories.
- Use dry-run for system proxy commands.
- Mock controller responses before testing live Mihomo APIs.
- Avoid tests that require a real network subscription.

## Areas That Need More Coverage

- CLI argument parsing.
- JSON output stability.
- Mihomo controller response mapping.
- Profile import and remote refresh errors.
- Missing core path errors.
- UI store behavior.
- Future Unix socket transport.

## Quality Rules

- Keep `KumoCoreKit` independent from SwiftUI.
- Keep command execution isolated.
- Use explicit errors instead of generic failures.
- Keep advanced features behind advanced UI.
- Prefer small files grouped by domain responsibility.

## Manual QA Checklist

- `kumo status --json` returns valid JSON.
- Missing Mihomo core shows a clear error.
- Empty profile still generates a safe direct config.
- System proxy dry-run prints the expected commands.
- SwiftUI window opens with Overview selected.
- Settings opens with Cmd+,.
- MenuBarExtra exposes start, stop, refresh, and system proxy controls.

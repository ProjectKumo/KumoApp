# Kumo Agent Guidelines

## Development Documentation

Use these documents as the project map before making architectural, runtime, UI, or workflow changes:

- `docs/README.md` — documentation index.
- `docs/product/information-architecture.md` — product scope and information architecture.
- `docs/interfaces/macos-swiftui-interface.md` — macOS SwiftUI interface structure and navigation.
- `docs/interfaces/cli-agent-control.md` — CLI and agent-control surfaces.
- `docs/core/control-layer.md` — core lifecycle and control boundaries.
- `docs/core/mihomo-runtime-controller.md` — Mihomo runtime controller behavior.
- `docs/core/profiles-runtime-configuration.md` — profile import, metadata, and runtime configuration flow.
- `docs/operations/system-integration-permissions.md` — macOS permissions and system integration.
- `docs/operations/persistence-logging.md` — persistence, state files, and logging.
- `docs/operations/release-management.md` — release artifacts and app update flow.
- `docs/roadmap/service-mode-roadmap.md` — service-mode direction and staged roadmap.
- `docs/quality/testing-quality.md` — testing and quality expectations.

SwiftUI-specific implementation guidance lives under `.agents/skills/`, especially:

- `.agents/skills/swiftui-expert-skill/SKILL.md`
- `.agents/skills/macos-design-guidelines/SKILL.md`
- `.agents/skills/swiftui-liquid-glass/SKILL.md`
- `.agents/skills/liquid-glass-design/SKILL.md`
- `.agents/skills/swiftui-animation/SKILL.md`
- `.agents/skills/swiftui-ui-patterns/SKILL.md`
- `.agents/skills/swiftui-view-refactor/SKILL.md`
- `.agents/skills/swiftui-performance-audit/SKILL.md`

## Documentation Maintenance

When a change meaningfully alters product behavior, architecture, runtime configuration, persistence, permissions, testing expectations, or UI information architecture, update the relevant document in `docs/` in the same change set. Do not let implementation and documentation drift.

## UI Copy Constraints

- Avoid redundant copy. Do not repeat information already expressed by a title, metric, selected state, icon, or surrounding section.
- Prefer concise labels over explanatory text when the UI state is self-evident.
- Remove disabled placeholder actions unless they teach a real next step.
- Do not add low-information detail text such as "Current profile", "selected", or repeated counts when nearby UI already communicates the same fact.
- Keep user-visible copy in English unless explicitly asked otherwise.

## SwiftUI Native Component Constraints

- Prefer native SwiftUI and macOS controls (`NavigationSplitView`, `List`, `Table`, `Form`, `Menu`, `Button`, `Picker`, `Toggle`, `PasteButton`) before custom components.
- Do not recreate native selection, toolbar, menu, sidebar, or button behavior with overlays, fake masks, or hand-rolled hit targets.
- For Liquid Glass, prefer native APIs (`glassEffect`, `GlassEffectContainer`, `glassEffectID`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`) and apply interactive glass only to interactive elements.
- Keep custom views small and compositional. Extract only when it clarifies state, layout, or reuse.

---
name: add-component
description: >
  Add a SwiftUI component from ShipSwift recipes. Use when the user says "add component",
  "add a view", "add X view", "I need a chart", "add animation", or wants a specific UI element.
---

# Add Component from ShipSwift

Add production-ready SwiftUI components to your project using ShipSwift's recipe library. Each recipe is a complete, copy-paste-ready implementation with architecture documentation.

## Prerequisites Check

Before starting, verify the ShipSwift recipe server is available by calling `listRecipes`.

If the tools are not available, guide the user to visit [shipswift.app](https://shipswift.app) for setup instructions, or run `npx skills add signerlabs/shipswift-skills` to install.

## Workflow

1. **Identify the component type**: Determine what kind of component the user needs:
   - **Animation**: shimmer, typewriter, glow-scan, shaking-icon, mesh-gradient, orbit, scan, viewfinder, before-after
   - **Chart**: line, bar, area, donut, ring, radar, scatter, heatmap
   - **UI Component**: label, alert, loading, stepper, onboarding, tab-button, and more
   - **Module**: auth, camera, chat, settings, subscriptions, infrastructure

2. **Search for the recipe**: Use `searchRecipes` with the component name or type. For example:
   - User says "add a donut chart" -> search "donut"
   - User says "add shimmer loading" -> search "shimmer"
   - User says "add authentication" -> search "auth"

3. **Fetch the full recipe**: Use `getRecipe` with the recipe ID to get the complete implementation, including:
   - Full Swift source code
   - Architecture explanation
   - Integration steps
   - Known gotchas

4. **Integrate into the project**: Adapt the recipe code to fit the user's project:
   - Match existing naming conventions
   - Connect to the user's data models
   - Adjust styling to match the app's design system

5. **Verify integration**: Walk through the recipe's integration checklist to ensure nothing is missed (dependencies, Info.plist entries, etc.).

## Guidelines

- Use `SW`-prefixed type names for ShipSwift components (e.g., `SWDonutChart`, `SWTypewriter`).
- View modifier methods use `.sw` lowercase prefix (e.g., `.swShimmer()`, `.swGlowScan()`).
- Charts components use a generic `CategoryType` pattern with `String` convenience initializer.
- For chart animations, use the `.mask()` approach with animated `Rectangle` width via `GeometryReader` -- Swift Charts does not support built-in line draw animation.
- Internal helper types should be `private` and use the `SW` prefix.
- Add `cornerRadius` parameter when components clip content.
- Support both struct initializer and View modifier API for overlay-type components.

## Pro Recipes

Some recipes require a Pro license ($89 one-time). If a recipe returns a purchase prompt, the user can buy at [shipswift.app/pricing](https://shipswift.app/pricing) and set `SHIPSWIFT_API_KEY` in their environment.

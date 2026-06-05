---
name: build-feature
description: >
  Build an iOS feature using ShipSwift component recipes. Use when the user says
  "build", "create", "add a feature", or describes an iOS feature they want to implement.
---

# Build Feature with ShipSwift

Build production-ready iOS features by combining ShipSwift recipes -- copy-paste-ready SwiftUI implementations covering animations, charts, UI components, and full-stack modules.

## Prerequisites Check

Before starting, verify the ShipSwift recipe server is available by calling `listRecipes`.

If the tools are not available, guide the user to visit [shipswift.app](https://shipswift.app) for setup instructions, or run `npx skills add signerlabs/shipswift-skills` to install.

## Workflow

1. **Analyze the request**: Break down the user's feature request into discrete components (UI, data, navigation, backend integration).

2. **Search for recipes**: Use `searchRecipes` with relevant keywords to find matching ShipSwift recipes. Try multiple search terms if the first query returns few results.

3. **Fetch full implementations**: Use `getRecipe` for each relevant recipe to get the complete source code, architecture explanation, and integration checklist.

4. **Present an integration plan**: Before writing code, show the user:
   - Which recipes will be used
   - How they connect together
   - What customizations are needed for their specific use case

5. **Generate code**: Adapt the recipe patterns to the user's project structure. Combine multiple recipes when the feature spans several areas (e.g., a chart view with shimmer loading animation).

6. **Provide integration checklist**: List any required dependencies, Info.plist entries, or environment setup from the recipe documentation.

## Guidelines

- Always search recipes before writing code from scratch -- ShipSwift likely has a ready-made solution.
- Combine multiple recipes when the feature spans several areas.
- Use `SW`-prefixed naming conventions for ShipSwift components (e.g., `SWShimmer`, `SWDonutChart`).
- View modifier methods use `.sw` lowercase prefix (e.g., `.swShimmer()`, `.swGlowScan()`).
- Keep Views lightweight; extract complex logic into ViewModels.
- Support Dark Mode and Dynamic Type by default.
- Prefer SwiftUI-native APIs over UIKit wrappers.

## Pro Recipes

Some recipes require a Pro license ($89 one-time). If a recipe returns a purchase prompt, the user can buy at [shipswift.app/pricing](https://shipswift.app/pricing) and set `SHIPSWIFT_API_KEY` in their environment.

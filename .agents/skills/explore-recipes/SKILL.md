---
name: explore-recipes
description: Explore and browse available ShipSwift recipes. Use when the user says explore, browse, show recipes, list components, what's available, or wants to discover what ShipSwift offers.
---

# Explore ShipSwift Recipes

Browse the full catalog of ShipSwift recipes -- production-ready SwiftUI implementations covering animations, charts, UI components, and full-stack modules.

## Prerequisites Check

Before starting, verify the ShipSwift recipe server is available by calling `listRecipes`.

If the tools are not available, guide the user to visit [shipswift.app](https://shipswift.app) for setup instructions, or run `npx skills add signerlabs/shipswift-skills` to install.

## Workflow

1. **List available recipes**: Use `listRecipes` to get the full catalog. Present them organized by category:

   | Category | Count | Examples |
   |----------|-------|---------|
   | Animation | 10 | Shimmer, Typewriter, Glow Scan, Mesh Gradient |
   | Chart | 8 | Line, Bar, Area, Donut, Radar, Heatmap |
   | Component | 14 | Label, Alert, Loading, Stepper, Onboarding |
   | Module | 8 | Auth, Camera, Chat, Settings, Subscriptions |

2. **Filter by category** (optional): If the user is interested in a specific category, use `listRecipes` with the category filter or `searchRecipes` with relevant keywords.

3. **Show recipe details**: When the user picks a recipe, use `getRecipe` to fetch the full implementation and present:
   - What the component does
   - Architecture overview
   - Key features and customization options
   - A preview of the code structure

4. **Suggest combinations**: Based on the user's project, recommend recipe combinations that work well together. For example:
   - **Onboarding flow**: onboarding-view + typewriter-text + shimmer
   - **Analytics dashboard**: line-chart + bar-chart + donut-chart + activity-heatmap
   - **Social feature**: camera + chat + auth-cognito

## Guidelines

- Present recipes in a scannable format (tables or bullet lists).
- Highlight the recipe tier (Free or Pro) so users know what's included.
- When showing recipe details, include the recipe ID so the user can reference it later.
- Suggest relevant recipes based on the user's current project context.

## Pro Recipes

Some recipes require a Pro license ($89 one-time). If a recipe returns a purchase prompt, the user can buy at [shipswift.app/pricing](https://shipswift.app/pricing) and set `SHIPSWIFT_API_KEY` in their environment.

# macOS SwiftUI Interface

## Scope

`KumoApp` is the native macOS frontend. It owns windows, menus, Settings, MenuBarExtra, and SwiftUI state coordination. It does not own Mihomo lifecycle or profile generation; those responsibilities live in `KumoCoreKit`.

## App Scene Structure

The app uses:

- `WindowGroup` for the primary resizable Mac window.
- `Settings` for preferences reachable through the standard app menu.
- `MenuBarExtra` for lightweight status and quick actions.
- `CommandMenu` for keyboard-accessible Kumo commands.

The main window keeps standard macOS chrome, a unified toolbar, and a sensible minimum size.

## View Structure

`ContentView` uses `NavigationSplitView` with four destinations:

- `OverviewView`
- `ProxiesView`
- `ProfilesView`
- `AdvancedView`

`KumoAppStore` is an `@Observable` object that bridges SwiftUI state to `KumoCoreKit`. Views should call store methods instead of directly constructing controller clients.

## Liquid Glass Usage

Liquid Glass is used sparingly:

- Status cards
- Interactive proxy chips
- Main grouped controls

The implementation provides fallback material backgrounds for older macOS versions. Interactive glass is only used on controls that perform actions.

## Accessibility

All icon-only controls should have meaningful labels. The toolbar uses `Label` so VoiceOver and tooltips have clear names. The app should also preserve keyboard access for start, stop, refresh, and mode switching.

## Design Constraints

- Avoid dense dashboards.
- Keep advanced panels secondary.
- Prefer system fonts, semantic colors, and standard controls.
- Preserve window resizing and standard traffic light buttons.

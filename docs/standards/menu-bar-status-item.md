# Menu Bar Status Item

Kumo uses an AppKit `NSStatusItem` for the persistent menu bar icon. Do not add a SwiftUI `MenuBarExtra` scene beside it; that creates duplicate icons and limits runtime control over the menu.

## Structure

- `KumoAppDelegate` owns the lifetime of `KumoStatusItemController`.
- `KumoStatusItemController` owns the `NSStatusItem`, status icon, and `NSMenuDelegate`.
- `KumoAppContext` bridges the SwiftUI-owned `KumoAppStore`, main window action, and Settings action to AppKit callbacks.

## Menu Requirements

The menu should rebuild before it opens so checked states and enabled states reflect current runtime data. Keep these top-level actions available:

- Open Kumo
- Start / Stop Kumo
- Outbound Mode submenu with Rule / Global / Direct checkmarks
- System Proxy toggle with a checkmark
- Profiles submenu
- Proxy Groups submenu
- Refresh
- Settings
- About Kumo
- Quit Kumo

Use native `NSMenuItem.state` checkmarks for selected modes, profiles, proxies, and system proxy state. Keep disabled empty-state items concise, such as "No profiles" or "No proxy groups".

## Visual Requirements

Use a template status icon so macOS can adapt it for light mode, dark mode, and menu bar contrast. Runtime state can be expressed by the status icon symbol, tooltip, and menu status rows rather than colored custom artwork.

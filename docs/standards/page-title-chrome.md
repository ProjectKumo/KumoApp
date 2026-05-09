# Page Titles and Window Chrome

Kumo uses the macOS toolbar / navigation title as the primary page title surface. Detail pages should not repeat the same title as a large heading inside the content area.

## Rule

Every top-level destination should expose its title through `ContentView` navigation chrome. The page content should begin with the first meaningful control, summary card, form section, table, or empty state.

Do not add a duplicate in-page large title such as:

```swift
Text("Proxies")
    .font(.largeTitle.bold())
```

The shared `KumoPage(title:)` wrapper keeps the `title` argument for call-site readability, but it must not render that title as content. It is a content layout wrapper, not a second title bar.

## Rationale

macOS windows already provide a clear title region in the unified toolbar. Repeating the same destination name inside the page consumes vertical space, weakens hierarchy, and makes card-heavy pages feel like a nested sheet under a separate heading.

## Exceptions

Use an in-page heading only when it names a subsection that is not already represented by the window or navigation title. Section headings inside `Form`, `Table`, cards, and grouped controls remain appropriate.

## Checklist

Before shipping a new or refactored page:

- The destination title is visible in the toolbar / navigation chrome.
- The content area does not repeat the same title as a large heading.
- `KumoPage(title:)` is not used as a reason to render a second page title.
- Empty states still provide their own state-specific title, such as `No Proxy Groups`.

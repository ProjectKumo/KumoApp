# Proxies Page Scroll Container

The `Proxies` page uses a card-heavy, scroll-first layout. The proxy group cards must read as one continuous full-page content region, not as a nested card sheet under a separate in-page title.

## Rule

When proxy groups are available, the `Proxies` page must use a single full-page `ScrollView` for the proxy group card list.

Do not wrap the populated state in `KumoPage(title:)` with a nested scroll view. That structure makes only the card region appear to have the full-page background/shadow treatment. Also do not add an in-page `Text("Proxies")` heading; the destination title belongs to the toolbar / navigation chrome.

## Current Pattern

`ProxiesView` keeps the empty state on `KumoPage(title:)`, because the empty state should stay centered in the available page space.

For the populated state, `scrollContent` owns the whole page:

```swift
ScrollView {
    LazyVStack(spacing: 18) {
        // Proxy group cards
    }
    .padding(.bottom, 8)
}
.contentMargins(.horizontal, 24, for: .scrollContent)
.contentMargins(.top, 24, for: .scrollContent)
.contentMargins(.bottom, 32, for: .scrollContent)
.scrollEdgeEffectStyleIfAvailable()
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
```

## Visual Requirements

- The region should fill the detail pane horizontally and vertically.
- The first proxy group card must align with the standard 24 pt page margin.
- The bottom content margin should leave breathing room after the last card.
- The empty state may continue using the shared `KumoPage` wrapper.
- The page must follow [Page Titles and Window Chrome](page-title-chrome.md).

## Regression Checklist

Before shipping changes to `ProxiesView`, verify:

- There is no `KumoPage(title: "Proxies")` wrapping the populated card list.
- There is no duplicate in-page `Proxies` large title.
- Scrolling uses the full-page content region, not a nested card-only scroll area.
- The card background/shadow treatment visually covers the whole populated content region.
- Search in the toolbar does not change the container hierarchy.

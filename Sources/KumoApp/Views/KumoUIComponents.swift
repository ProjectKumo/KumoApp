import SwiftUI

struct KumoPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct KumoEmptyState<Action: View>: View {
    let title: String
    let systemImage: String
    let message: String
    @ViewBuilder let action: Action

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct KumoInlineState<Action: View>: View {
    let title: String
    let systemImage: String
    let message: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                action
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 14)
    }
}

struct StatusPill: View {
    @Environment(\.legibilityWeight) private var legibilityWeight
    let title: String
    let value: String
    var systemImage: String?
    var showsMenuIndicator = false
    var showsSurface = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .fontWeight(legibilityWeight == .bold ? .bold : .medium)
                .contentTransition(.numericText())
                .lineLimit(1)
                .truncationMode(.middle)
            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(StatusPillSurfaceModifier(isInteractive: showsMenuIndicator, showsSurface: showsSurface))
    }
}

private struct StatusPillSurfaceModifier: ViewModifier {
    let isInteractive: Bool
    let showsSurface: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsSurface {
            if isInteractive {
                content.kumoInteractiveGlass(cornerRadius: 10)
            } else {
                content.kumoGlassCard(cornerRadius: 10)
            }
        } else {
            content
        }
    }
}

struct CompactSettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension Int {
    var kumoByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary)
    }
}

// MARK: - Accessibility helpers

/// Apply a heavier font weight when Bold Text is enabled in System Settings.
struct AdaptiveTextWeightModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight
    let regular: Font.Weight
    let bold: Font.Weight

    func body(content: Content) -> some View {
        content.fontWeight(legibilityWeight == .bold ? bold : regular)
    }
}

extension View {
    /// Pick a font weight that respects the user's Bold Text accessibility
    /// preference. Standard SwiftUI text styles handle this automatically;
    /// use this on any text where a custom weight is applied.
    func kumoAdaptiveTextWeight(regular: Font.Weight = .regular, bold: Font.Weight = .semibold) -> some View {
        modifier(AdaptiveTextWeightModifier(regular: regular, bold: bold))
    }
}

/// A pair of colors picked based on the user's Increase Contrast preference.
struct AdaptiveContrastColor {
    let standard: Color
    let increased: Color

    func resolve(contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? increased : standard
    }
}

/// Apply a translucent secondary fill that becomes more opaque when the
/// user has Increase Contrast enabled, so subtle pill / divider surfaces
/// remain visible to users who need higher contrast.
struct KumoSubtleBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let standardOpacity: Double
    let increasedOpacity: Double

    func body(content: Content) -> some View {
        content.background(
            Color.secondary.opacity(contrast == .increased ? increasedOpacity : standardOpacity),
            in: shape
        )
    }
}

extension View {
    /// A subtle secondary-tinted background that adapts to Increase Contrast.
    func kumoSubtleBackground<S: Shape>(
        in shape: S,
        standardOpacity: Double = 0.10,
        increasedOpacity: Double = 0.24
    ) -> some View {
        modifier(KumoSubtleBackgroundModifier(
            shape: shape,
            standardOpacity: standardOpacity,
            increasedOpacity: increasedOpacity
        ))
    }
}

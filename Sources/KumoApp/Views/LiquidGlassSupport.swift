import AppKit
import SwiftUI

private struct KumoGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let fallbackMaterial: Material
    let isInteractive: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(reducedTransparencyColor, in: .rect(cornerRadius: cornerRadius))
        } else if #available(macOS 26.0, *) {
            if isInteractive {
                if let tint {
                    content.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                }
            } else {
                if let tint {
                    content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                } else {
                    content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
            }
        } else {
            content.background(fallbackMaterial, in: .rect(cornerRadius: cornerRadius))
                .background(tint.opacityOrClear, in: .rect(cornerRadius: cornerRadius))
        }
    }

    private var reducedTransparencyColor: Color {
        tint ?? Color(nsColor: .controlBackgroundColor)
    }
}

extension View {
    func kumoGlassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(KumoGlassSurfaceModifier(cornerRadius: cornerRadius, fallbackMaterial: .ultraThinMaterial, isInteractive: false, tint: tint))
    }

    func kumoInteractiveGlass(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(KumoGlassSurfaceModifier(cornerRadius: cornerRadius, fallbackMaterial: .thinMaterial, isInteractive: true, tint: tint))
    }

    @ViewBuilder
    func kumoGlassMenuButton(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *) {
            self
                .menuStyle(.button)
                .buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.plain)
                .kumoInteractiveGlass(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    func kumoGlassButton(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
                .buttonStyle(.plain)
                .kumoInteractiveGlass(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    func kumoLiquidGlassTabViewStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }

    @ViewBuilder
    func kumoGlassEffectID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

private extension Optional where Wrapped == Color {
    var opacityOrClear: Color {
        switch self {
        case .some(let color):
            color.opacity(0.14)
        case .none:
            .clear
        }
    }
}

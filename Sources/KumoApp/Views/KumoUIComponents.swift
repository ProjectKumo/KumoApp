import SwiftUI

struct KumoPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.bold())
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
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
        .frame(maxWidth: 380, alignment: .leading)
        .kumoGlassCard(cornerRadius: 14)
    }
}

struct StatusPill: View {
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
            Text(value)
                .fontWeight(.medium)
            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

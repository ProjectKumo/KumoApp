import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct ControllerSecretField: View {
    let currentSecret: String
    let commit: (String) -> Void
    @State private var draft: String = ""
    @State private var hasChanges = false

    var body: some View {
        HStack {
            SecureField("Controller Secret", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft) { _, _ in
                    hasChanges = draft != currentSecret
                }
                .onSubmit { applyIfNeeded() }
            Button("Apply") {
                applyIfNeeded()
            }
            .disabled(!hasChanges)
        }
        .onAppear {
            draft = currentSecret
            hasChanges = false
        }
        .onChange(of: currentSecret) { _, newValue in
            // Sync only when the user has not typed pending changes,
            // otherwise the in-progress edit would be clobbered by store
            // updates triggered elsewhere.
            if !hasChanges {
                draft = newValue
            }
        }
    }

    private func applyIfNeeded() {
        guard hasChanges else { return }
        commit(draft)
        hasChanges = false
    }
}

struct ProviderRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}


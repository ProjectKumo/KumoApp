import SwiftUI
import KumoCoreKit

/// Lightweight editor for Sub-Store `process` arrays. Each entry is a JSON
/// value of the shape `{ "type": "...", "args": {...} }`. The editor lets the
/// user pick a known operator type, edit the `args` payload as JSON, reorder
/// entries, and add/remove rows. Unknown JSON fields on each entry are
/// preserved on round-trip so user-authored hand-tuned operators keep working.
struct ProcessPipelineEditor: View {
    @Binding var pipeline: [JSONValue]
    @State private var addingType: String = OperatorCatalog.commonTypes.first ?? "Script Operator"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Process Pipeline")
                .font(.headline)
            if pipeline.isEmpty {
                Text("No operators configured. Sub-Store will return raw nodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(pipeline.enumerated()), id: \.offset) { index, _ in
                    ProcessOperatorRow(
                        operator: binding(for: index),
                        moveUp: index > 0 ? { swap(index, index - 1) } : nil,
                        moveDown: index < pipeline.count - 1 ? { swap(index, index + 1) } : nil,
                        remove: { remove(index) }
                    )
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            HStack {
                Picker("Operator type", selection: $addingType) {
                    ForEach(OperatorCatalog.commonTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                Button("Add Operator") {
                    pipeline.append(.object([
                        "type": .string(addingType),
                        "args": .object([:])
                    ]))
                }
            }
        }
    }

    private func binding(for index: Int) -> Binding<JSONValue> {
        Binding {
            pipeline.indices.contains(index) ? pipeline[index] : .object([:])
        } set: { newValue in
            guard pipeline.indices.contains(index) else { return }
            pipeline[index] = newValue
        }
    }

    private func swap(_ a: Int, _ b: Int) {
        guard pipeline.indices.contains(a), pipeline.indices.contains(b) else { return }
        pipeline.swapAt(a, b)
    }

    private func remove(_ index: Int) {
        guard pipeline.indices.contains(index) else { return }
        pipeline.remove(at: index)
    }
}

private struct ProcessOperatorRow: View {
    @Binding var `operator`: JSONValue
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let remove: () -> Void

    @State private var argsText: String = ""
    @State private var argsError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Type", text: typeBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button {
                    moveUp?()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(moveUp == nil)
                Button {
                    moveDown?()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(moveDown == nil)
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("args (JSON)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $argsText)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                if let argsError {
                    Text(argsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task(id: argsTextSeed) {
            argsText = argsTextSeed
        }
        .onChange(of: argsText) {
            commit()
        }
    }

    private var typeBinding: Binding<String> {
        Binding {
            `operator`.objectValue?["type"]?.stringValue ?? ""
        } set: { newValue in
            updateField(key: "type", value: .string(newValue))
        }
    }

    private var argsTextSeed: String {
        guard let object = `operator`.objectValue,
              let args = object["args"] else {
            return "{}"
        }
        guard let data = try? JSONEncoder.subStorePretty.encode(args),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func commit() {
        guard let data = argsText.data(using: .utf8) else {
            argsError = "Invalid encoding"
            return
        }
        do {
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            updateField(key: "args", value: value)
            argsError = nil
        } catch {
            argsError = "JSON: \(error.localizedDescription)"
        }
    }

    private func updateField(key: String, value: JSONValue) {
        var object = `operator`.objectValue ?? [:]
        object[key] = value
        `operator` = .object(object)
    }
}

enum OperatorCatalog {
    static let commonTypes: [String] = [
        "Quick Setting Operator",
        "Type Filter",
        "Region Filter",
        "Regex Filter",
        "Includes Filter",
        "Excludes Filter",
        "Keyword Filter",
        "Conditional Filter",
        "Script Filter",
        "Sort Operator",
        "Regex Sort Operator",
        "Keyword Sort Operator",
        "Keyword Rename Operator",
        "Regex Rename Operator",
        "Handle Duplicate Operator",
        "Resolve Domain Operator",
        "Script Operator"
    ]
}

extension JSONEncoder {
    /// Pretty-printed encoder used by inline JSON editors.
    public static var subStorePretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

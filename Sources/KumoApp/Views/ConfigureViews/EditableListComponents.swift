import SwiftUI
import KumoCoreKit

// MARK: - Shared toolbar

/// Bottom +/- toolbar shared by the editable list and table components.
/// Renders a thin divider on top and macOS-style borderless icon buttons.
private struct EditableListToolbar: View {
    let onAdd: () -> Void
    let onRemove: () -> Void
    var canRemove: Bool
    var onEdit: (() -> Void)? = nil
    var canEdit: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 18)
                }
                .help("Add")

                Button(action: onRemove) {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 18)
                }
                .disabled(!canRemove)
                .help("Remove selected")

                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .frame(width: 22, height: 18)
                    }
                    .disabled(!canEdit)
                    .help("Edit selected")
                }

                Spacer()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - EditableStringList

/// Native list editor for a `[String]` collection.
/// Each row is an inline TextField; the bottom toolbar adds blank rows or
/// removes the current selection. Empty rows are allowed during editing
/// and are expected to be filtered by the calling view before persistence.
struct EditableStringList: View {
    @Binding var items: [String]
    var placeholder: String = "Item"
    var minHeight: CGFloat = 120
    var maxHeight: CGFloat = 240
    var monospaced: Bool = false
    var accessibilityLabel: String? = nil

    @State private var rows: [Row] = []
    @State private var selection: Set<UUID> = []
    @FocusState private var focusedRow: UUID?

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var value: String
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($rows) { $row in
                    TextField(placeholder, text: $row.value)
                        .textFieldStyle(.plain)
                        .font(monospaced ? .body.monospaced() : .body)
                        .focused($focusedRow, equals: row.id)
                        .tag(row.id)
                }
                .onDelete { offsets in rows.remove(atOffsets: offsets) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            EditableListToolbar(
                onAdd: addRow,
                onRemove: removeSelectedRows,
                canRemove: !selection.isEmpty
            )
        }
        .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
        .onAppear { syncRowsFromItems() }
        .onChange(of: items) { _, _ in syncRowsFromItems() }
        .onChange(of: rows) { _, newRows in
            let next = newRows.map(\.value)
            if next != items { items = next }
        }
    }

    private func syncRowsFromItems() {
        let current = rows.map(\.value)
        guard current != items else { return }
        rows = items.map { Row(value: $0) }
        selection.removeAll()
    }

    private func addRow() {
        let new = Row(value: "")
        rows.append(new)
        selection = [new.id]
        focusRow(new.id)
    }

    private func removeSelectedRows() {
        guard !selection.isEmpty else { return }
        rows.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func focusRow(_ id: UUID) {
        // Defer focus assignment so SwiftUI has appended the row before
        // FocusState attempts to match a TextField id.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            focusedRow = id
        }
    }
}

// MARK: - EditableIntList

/// Native list editor for an integer collection (e.g. sniffer ports).
/// Stores a `String` draft per row so partial input is preserved while typing;
/// rows that fail to parse are dropped from the committed `[Int]` until they parse cleanly.
struct EditableIntList: View {
    @Binding var values: [Int]
    var placeholder: String = "Value"
    var minHeight: CGFloat = 100
    var maxHeight: CGFloat = 200
    var accessibilityLabel: String? = nil

    @State private var rows: [Row] = []
    @State private var selection: Set<UUID> = []
    @FocusState private var focusedRow: UUID?

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var draft: String
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($rows) { $row in
                    TextField(placeholder, text: $row.draft)
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                        .focused($focusedRow, equals: row.id)
                        .tag(row.id)
                }
                .onDelete { offsets in rows.remove(atOffsets: offsets) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            EditableListToolbar(
                onAdd: addRow,
                onRemove: removeSelectedRows,
                canRemove: !selection.isEmpty
            )
        }
        .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
        .onAppear { syncRowsFromValues() }
        .onChange(of: values) { _, _ in syncRowsFromValues() }
        .onChange(of: rows) { _, newRows in
            let next = newRows.compactMap { Int($0.draft.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if next != values { values = next }
        }
    }

    private func syncRowsFromValues() {
        let parsed = rows.compactMap { Int($0.draft.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parsed != values else { return }
        rows = values.map { Row(draft: String($0)) }
        selection.removeAll()
    }

    private func addRow() {
        let new = Row(draft: "")
        rows.append(new)
        selection = [new.id]
        focusRow(new.id)
    }

    private func removeSelectedRows() {
        guard !selection.isEmpty else { return }
        rows.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func focusRow(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            focusedRow = id
        }
    }
}

// MARK: - PolicyDictEditor

/// Native two-line list editor for `[String: PolicyValue]` (Mihomo `nameserver-policy`, `hosts`).
/// Each row shows the key plus a one-line summary; tapping `+`/Edit opens a sheet that
/// switches between Single and Multiple value modes for clean round-tripping.
struct PolicyDictEditor: View {
    @Binding var entries: [String: PolicyValue]
    var minHeight: CGFloat = 140
    var maxHeight: CGFloat = 260
    var accessibilityLabel: String? = nil

    @State private var rows: [Row] = []
    @State private var selection: Set<UUID> = []
    @State private var editing: EditingSession?

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: PolicyValue
    }

    private enum EditingSession: Identifiable {
        case new
        case existing(UUID)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let uuid): return uuid.uuidString
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.key.isEmpty ? "(unnamed)" : row.key)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(row.key.isEmpty ? .secondary : .primary)
                        Spacer(minLength: 8)
                        Text(summary(for: row.value))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = .existing(row.id) }
                    .tag(row.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            EditableListToolbar(
                onAdd: { editing = .new },
                onRemove: removeSelectedRows,
                canRemove: !selection.isEmpty,
                onEdit: { if let id = selection.first { editing = .existing(id) } },
                canEdit: selection.count == 1
            )
        }
        .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
        .onAppear { syncRowsFromEntries() }
        .onChange(of: entries) { _, _ in syncRowsFromEntries() }
        .onChange(of: rows) { _, _ in commitFromRows() }
        .sheet(item: $editing) { session in
            switch session {
            case .new:
                PolicyEntrySheet(initialKey: "", initialValue: .single("")) { key, value in
                    rows.append(Row(key: key, value: value))
                }
            case .existing(let id):
                if let index = rows.firstIndex(where: { $0.id == id }) {
                    PolicyEntrySheet(
                        initialKey: rows[index].key,
                        initialValue: rows[index].value
                    ) { key, value in
                        rows[index].key = key
                        rows[index].value = value
                    }
                }
            }
        }
    }

    private func syncRowsFromEntries() {
        let current = collapse(rows)
        guard current != entries else { return }
        rows = entries
            .sorted(by: { $0.key < $1.key })
            .map { Row(key: $0.key, value: $0.value) }
        selection.removeAll()
    }

    private func commitFromRows() {
        let collapsed = collapse(rows)
        if collapsed != entries { entries = collapsed }
    }

    private func collapse(_ rows: [Row]) -> [String: PolicyValue] {
        var result: [String: PolicyValue] = [:]
        for row in rows {
            let trimmed = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result[trimmed] = row.value
        }
        return result
    }

    private func summary(for value: PolicyValue) -> String {
        switch value {
        case .single(let s):
            return s.isEmpty ? "(empty)" : s
        case .multiple(let arr):
            return arr.isEmpty ? "(empty list)" : arr.joined(separator: ", ")
        }
    }

    private func removeSelectedRows() {
        guard !selection.isEmpty else { return }
        rows.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
}

private struct PolicyEntrySheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case single
        case multiple

        var id: String { rawValue }

        var label: String {
            switch self {
            case .single: "Single Value"
            case .multiple: "Multiple Values"
            }
        }
    }

    let onSave: (String, PolicyValue) -> Void

    @State private var key: String
    @State private var mode: Mode
    @State private var singleValue: String
    @State private var multipleValues: [String]
    @Environment(\.dismiss) private var dismiss

    init(initialKey: String, initialValue: PolicyValue, onSave: @escaping (String, PolicyValue) -> Void) {
        self.onSave = onSave
        self._key = State(initialValue: initialKey)
        switch initialValue {
        case .single(let s):
            self._mode = State(initialValue: .single)
            self._singleValue = State(initialValue: s)
            self._multipleValues = State(initialValue: [])
        case .multiple(let arr):
            self._mode = State(initialValue: .multiple)
            self._singleValue = State(initialValue: "")
            self._multipleValues = State(initialValue: arr)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("Key", text: $key)
                }

                Section {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Value") {
                    if mode == .single {
                        TextField("Value", text: $singleValue)
                    } else {
                        EditableStringList(items: $multipleValues, placeholder: "Value")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Policy Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedKey.isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        let value: PolicyValue
        switch mode {
        case .single:
            value = .single(singleValue.trimmingCharacters(in: .whitespacesAndNewlines))
        case .multiple:
            value = .multiple(
                multipleValues
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }
        onSave(trimmedKey, value)
        dismiss()
    }
}

// MARK: - FallbackFilterDictEditor

/// Native list editor for `[String: FallbackFilterValue]` (Mihomo `fallback-filter`).
/// The sheet supports Boolean, Single, and Multiple value modes to preserve
/// the underlying Mihomo schema shape.
struct FallbackFilterDictEditor: View {
    @Binding var entries: [String: FallbackFilterValue]
    var minHeight: CGFloat = 140
    var maxHeight: CGFloat = 260
    var accessibilityLabel: String? = nil

    @State private var rows: [Row] = []
    @State private var selection: Set<UUID> = []
    @State private var editing: EditingSession?

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: FallbackFilterValue
    }

    private enum EditingSession: Identifiable {
        case new
        case existing(UUID)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let uuid): return uuid.uuidString
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.key.isEmpty ? "(unnamed)" : row.key)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(row.key.isEmpty ? .secondary : .primary)
                        Spacer(minLength: 8)
                        Text(summary(for: row.value))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = .existing(row.id) }
                    .tag(row.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            EditableListToolbar(
                onAdd: { editing = .new },
                onRemove: removeSelectedRows,
                canRemove: !selection.isEmpty,
                onEdit: { if let id = selection.first { editing = .existing(id) } },
                canEdit: selection.count == 1
            )
        }
        .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
        .onAppear { syncRowsFromEntries() }
        .onChange(of: entries) { _, _ in syncRowsFromEntries() }
        .onChange(of: rows) { _, _ in commitFromRows() }
        .sheet(item: $editing) { session in
            switch session {
            case .new:
                FallbackFilterEntrySheet(initialKey: "", initialValue: .bool(true)) { key, value in
                    rows.append(Row(key: key, value: value))
                }
            case .existing(let id):
                if let index = rows.firstIndex(where: { $0.id == id }) {
                    FallbackFilterEntrySheet(
                        initialKey: rows[index].key,
                        initialValue: rows[index].value
                    ) { key, value in
                        rows[index].key = key
                        rows[index].value = value
                    }
                }
            }
        }
    }

    private func syncRowsFromEntries() {
        let current = collapse(rows)
        guard current != entries else { return }
        rows = entries
            .sorted(by: { $0.key < $1.key })
            .map { Row(key: $0.key, value: $0.value) }
        selection.removeAll()
    }

    private func commitFromRows() {
        let collapsed = collapse(rows)
        if collapsed != entries { entries = collapsed }
    }

    private func collapse(_ rows: [Row]) -> [String: FallbackFilterValue] {
        var result: [String: FallbackFilterValue] = [:]
        for row in rows {
            let trimmed = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result[trimmed] = row.value
        }
        return result
    }

    private func summary(for value: FallbackFilterValue) -> String {
        switch value {
        case .bool(let b):
            return b ? "true" : "false"
        case .single(let s):
            return s.isEmpty ? "(empty)" : s
        case .multiple(let arr):
            return arr.isEmpty ? "(empty list)" : arr.joined(separator: ", ")
        }
    }

    private func removeSelectedRows() {
        guard !selection.isEmpty else { return }
        rows.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
}

private struct FallbackFilterEntrySheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case bool
        case single
        case multiple

        var id: String { rawValue }

        var label: String {
            switch self {
            case .bool: "Boolean"
            case .single: "Single Value"
            case .multiple: "Multiple Values"
            }
        }
    }

    let onSave: (String, FallbackFilterValue) -> Void

    @State private var key: String
    @State private var mode: Mode
    @State private var boolValue: Bool
    @State private var singleValue: String
    @State private var multipleValues: [String]
    @Environment(\.dismiss) private var dismiss

    init(initialKey: String, initialValue: FallbackFilterValue, onSave: @escaping (String, FallbackFilterValue) -> Void) {
        self.onSave = onSave
        self._key = State(initialValue: initialKey)
        switch initialValue {
        case .bool(let b):
            self._mode = State(initialValue: .bool)
            self._boolValue = State(initialValue: b)
            self._singleValue = State(initialValue: "")
            self._multipleValues = State(initialValue: [])
        case .single(let s):
            self._mode = State(initialValue: .single)
            self._boolValue = State(initialValue: false)
            self._singleValue = State(initialValue: s)
            self._multipleValues = State(initialValue: [])
        case .multiple(let arr):
            self._mode = State(initialValue: .multiple)
            self._boolValue = State(initialValue: false)
            self._singleValue = State(initialValue: "")
            self._multipleValues = State(initialValue: arr)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("Key", text: $key)
                }

                Section {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Value") {
                    switch mode {
                    case .bool:
                        Toggle("Enabled", isOn: $boolValue)
                    case .single:
                        TextField("Value", text: $singleValue)
                    case .multiple:
                        EditableStringList(items: $multipleValues, placeholder: "Value")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Fallback Filter Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedKey.isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        let value: FallbackFilterValue
        switch mode {
        case .bool:
            value = .bool(boolValue)
        case .single:
            value = .single(singleValue.trimmingCharacters(in: .whitespacesAndNewlines))
        case .multiple:
            value = .multiple(
                multipleValues
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }
        onSave(trimmedKey, value)
        dismiss()
    }
}

// MARK: - Helpers

private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        } else {
            content
        }
    }
}

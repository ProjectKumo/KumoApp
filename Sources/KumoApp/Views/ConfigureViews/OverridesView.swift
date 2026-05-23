import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct OverridesView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var remoteURL = ""
    @State private var isGlobal = false
    @State private var format: OverrideFormat = .yaml
    @State private var isImportingFile = false
    @State private var editingDraft: OverrideDraft?
    @State private var deletingOverride: OverrideItem?
    @State private var newDraft: NewOverrideDraft?

    var body: some View {
        KumoPage(title: "Overrides") {
            VStack(alignment: .leading, spacing: 12) {
                importControls

                if store.overrides.isEmpty {
                    KumoEmptyState(
                        title: "No Overrides",
                        systemImage: "slider.horizontal.3",
                        message: "Import or create a YAML override to modify the runtime profile."
                    ) {
                        Button(String(localized: "Choose File")) {
                            isImportingFile = true
                        }
                    }
                } else {
                    List(store.overrides) { item in
                        OverrideRow(
                            item: item,
                            onEdit: { openEditor(for: item) },
                            onDelete: { deletingOverride = item }
                        )
                    }
                    .scrollEdgeEffectStyleIfAvailable()
                }
            }
        }
        .task {
            store.refreshOverrides()
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let fileFormat: OverrideFormat = url.pathExtension.localizedCaseInsensitiveContains("js") ? .javascript : .yaml
                store.addLocalOverride(name: url.deletingPathExtension().lastPathComponent, format: fileFormat, content: content, isGlobal: isGlobal)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $editingDraft) { draft in
            OverrideEditorSheet(draft: draft) { editedDraft in
                store.updateOverride(editedDraft.item, content: editedDraft.content)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .sheet(item: $newDraft) { draft in
            NewOverrideSheet(draft: draft) { editedDraft in
                let template = editedDraft.format == .yaml ? "# Kumo YAML override\n" : "// Kumo JavaScript override\n"
                store.addLocalOverride(
                    name: editedDraft.name,
                    format: editedDraft.format,
                    content: template,
                    isGlobal: editedDraft.isGlobal
                )
                newDraft = nil
            } onCancel: {
                newDraft = nil
            }
        }
        .confirmationDialog(String(localized: "Delete Override?"),
            isPresented: Binding {
                deletingOverride != nil
            } set: { isPresented in
                if !isPresented {
                    deletingOverride = nil
                }
            },
            presenting: deletingOverride
        ) { item in
            Button(String(localized: "Delete \(item.name)"), role: .destructive) {
                store.deleteOverride(item)
                deletingOverride = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                deletingOverride = nil
            }
        } message: { _ in
            Text(String(localized: "This removes the local override file and metadata."))
        }
    }

    private var importControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                remoteOverrideURLField
                overrideOptions
                overrideActionGroup
            }

            VStack(alignment: .leading, spacing: 8) {
                remoteOverrideURLField
                HStack(spacing: 8) {
                    overrideOptions
                    Spacer()
                    overrideActionGroup
                }
            }
        }
    }

    private var remoteOverrideURLField: some View {
        TextField("Remote override URL", text: $remoteURL)
            .textFieldStyle(.roundedBorder)
    }

    private var overrideOptions: some View {
        HStack(spacing: 8) {
            Picker(String(localized: "Format"), selection: $format) {
                Text(String(localized: "YAML")).tag(OverrideFormat.yaml)
                Text(String(localized: "JavaScript")).tag(OverrideFormat.javascript)
            }
            .frame(width: 140)

            Toggle(String(localized: "Global"), isOn: $isGlobal)
                .toggleStyle(.checkbox)
                .fixedSize()
        }
    }

    private var overrideActionGroup: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Import URL")) {
                Task {
                    await store.addRemoteOverride(urlString: remoteURL, format: format, isGlobal: isGlobal)
                    if store.errorMessage == nil {
                        remoteURL = ""
                    }
                }
            }
            .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)

            Button(String(localized: "Import File…")) {
                isImportingFile = true
            }

            Button(String(localized: "New…")) {
                newDraft = NewOverrideDraft(isGlobal: isGlobal)
            }
        }
    }

    private func openEditor(for item: OverrideItem) {
        guard let content = store.overrideContent(id: item.id) else {
            return
        }
        editingDraft = OverrideDraft(item: item, content: content)
    }
}

private struct OverrideRow: View {
    let item: OverrideItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.format == .yaml ? "doc.text" : "curlybraces")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(String(format: String(localized: "%@ · %@"), item.kind.rawValue.capitalized, item.format.rawValue.uppercased()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isGlobal {
                Text(String(localized: "Global"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button(String(localized: "Edit")) { onEdit() }
                Divider()
                Button(String(localized: "Delete"), role: .destructive) { onDelete() }
            } label: {
                Label(String(localized: "More"), systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .contextMenu {
                Button(String(localized: "Edit")) { onEdit() }
                Button(String(localized: "Delete"), role: .destructive) { onDelete() }
            }
        }
    }
}

private struct NewOverrideDraft: Identifiable {
    let id = UUID()
    var name: String = "New Override"
    var format: OverrideFormat = .yaml
    var isGlobal: Bool

    init(isGlobal: Bool) {
        self.isGlobal = isGlobal
    }
}

private struct NewOverrideSheet: View {
    @State private var draft: NewOverrideDraft
    let onCreate: (NewOverrideDraft) -> Void
    let onCancel: () -> Void

    init(draft: NewOverrideDraft, onCreate: @escaping (NewOverrideDraft) -> Void, onCancel: @escaping () -> Void) {
        self._draft = State(initialValue: draft)
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "New Override"))
                .font(.title2.weight(.semibold))
                .padding(.horizontal)
                .padding(.top)

            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker(String(localized: "Format"), selection: $draft.format) {
                        Text(String(localized: "YAML")).tag(OverrideFormat.yaml)
                        Text(String(localized: "JavaScript")).tag(OverrideFormat.javascript)
                    }
                    Toggle(String(localized: "Global Override"), isOn: $draft.isGlobal)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    onCancel()
                }
                Button(String(localized: "Create")) {
                    onCreate(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 420)
    }
}

private struct OverrideDraft: Identifiable {
    var item: OverrideItem
    var content: String

    var id: String { item.id }
}

private struct OverrideEditorSheet: View {
    @State private var draft: OverrideDraft
    let onSave: (OverrideDraft) -> Void
    let onCancel: () -> Void

    init(draft: OverrideDraft, onSave: @escaping (OverrideDraft) -> Void, onCancel: @escaping () -> Void) {
        self._draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section(String(localized: "Info")) {
                    TextField("Name", text: $draft.item.name)
                    Toggle(String(localized: "Global Override"), isOn: $draft.item.isGlobal)
                    LabeledContent("Format", value: draft.item.format.rawValue.uppercased())
                    if let remoteURL = draft.item.remoteURL {
                        LabeledContent("Remote URL", value: remoteURL.absoluteString)
                    }
                }

                Section(String(localized: "Content")) {
                    TextEditor(text: $draft.content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 360)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    onCancel()
                }
                Button(String(localized: "Save")) {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 640, minHeight: 560)
    }
}

private struct ProfileBackedConfigPage: View {
    let title: String
    let systemImage: String
    let rows: [(String, String)]
    let onNavigate: (SidebarDestination) -> Void

    var body: some View {
        KumoPage(title: title) {
            Form {
                Section(String(localized: "Status")) {
                    ForEach(rows, id: \.0) { row in
                        LabeledContent(row.0, value: row.1)
                    }
                }

                Section {
                    Button {
                        onNavigate(.profiles)
                    } label: {
                        Label(String(localized: "Edit in Profile YAML"), systemImage: systemImage)
                    }
                } footer: {
                    Text(String(format: String(localized: "%@ is configured in the active profile."), title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

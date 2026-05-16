import SwiftUI
import KumoCoreKit

// MARK: - Files section

struct SubStoreFilesSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var editing: SubStoreFile?
    @State private var creatingNew = false

    var body: some View {
        @Bindable var subStore = subStore
        HStack(spacing: 0) {
            list(selection: $subStore.selection)
                .frame(width: 320)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $creatingNew) {
            FileEditorSheet(original: nil) { draft in
                await subStore.saveFile(name: nil, draft: draft)
            }
        }
        .sheet(item: $editing) { draft in
            FileEditorSheet(original: draft) { updated in
                await subStore.saveFile(name: draft.name, draft: updated)
            }
        }
    }

    private func list(selection: Binding<SubStoreStore.Selection?>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.files.count) files")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { creatingNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New file")
                Button {
                    Task { await subStore.refreshFiles() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh files")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: selection) {
                ForEach(subStore.files) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.resolvedDisplayName)
                            .font(.headline)
                        Text(file.source ?? "remote")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SubStoreStore.Selection.file(file.name))
                    .contextMenu {
                        Button("Edit…") { editing = file }
                        Divider()
                        Button("Delete", role: .destructive) {
                            Task { await subStore.deleteFile(name: file.name) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .file(let name) = subStore.selection,
           let file = subStore.files.first(where: { $0.name == name }) {
            FileDetail(file: file, onEdit: { editing = file })
        } else {
            ContentUnavailableView("Select a file", systemImage: "doc.text")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FileDetail: View {
    @Environment(SubStoreStore.self) private var subStore
    let file: SubStoreFile
    let onEdit: () -> Void
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(file.resolvedDisplayName)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { deleting = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let type = file.type, !type.isEmpty {
                            LabeledRow(label: "Type", value: type)
                        }
                        if let source = file.source, !source.isEmpty {
                            LabeledRow(label: "Source", value: source)
                        }
                        if let url = file.url, !url.isEmpty {
                            LabeledRow(label: "URLs", value: url)
                        }
                        if let ua = file.ua, !ua.isEmpty {
                            LabeledRow(label: "User-Agent", value: ua)
                        }
                        if let proxy = file.proxy, !proxy.isEmpty {
                            LabeledRow(label: "Proxy", value: proxy)
                        }
                        if let merge = file.mergeSources, !merge.isEmpty {
                            LabeledRow(label: "Merge Sources", value: merge)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyleIfAvailable()
        .confirmationDialog("Delete \(file.resolvedDisplayName)?", isPresented: $deleting) {
            Button("Delete Permanently", role: .destructive) {
                Task { await subStore.deleteFile(name: file.name) }
                deleting = false
            }
            Button("Cancel", role: .cancel) { deleting = false }
        }
    }
}

// MARK: - File editor

private struct FileEditorSheet: View {
    let original: SubStoreFile?
    let onSave: (SubStoreFile) async -> Bool

    @State private var draft: FileDraft
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(original: SubStoreFile?, onSave: @escaping (SubStoreFile) async -> Bool) {
        self.original = original
        self.onSave = onSave
        self._draft = State(initialValue: FileDraft(model: original))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $draft.name)
                    TextField("Display Name", text: $draft.displayName)
                    TextField("Type", text: $draft.type, prompt: Text("e.g. mihomoProfile, snippet"))
                }

                Picker("Source", selection: $draft.source) {
                    Text("Remote").tag("remote")
                    Text("Local").tag("local")
                }

                if draft.source == "remote" {
                    Section("URLs") {
                        EditableStringList(
                            items: $draft.urls,
                            placeholder: "https://provider.example/file",
                            monospaced: true,
                            accessibilityLabel: "File URLs"
                        )
                    }

                    Section("Remote") {
                        TextField("User-Agent", text: $draft.ua, prompt: Text("Optional"))
                    }
                }

                Section("Local Content") {
                    TextEditor(text: $draft.content)
                        .font(.body.monospaced())
                        .frame(minHeight: 180)
                }

                Section("Behavior") {
                    TextField("Proxy", text: $draft.proxy, prompt: Text("Optional"))
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(original == nil ? "New File" : "Edit \(original?.resolvedDisplayName ?? "")")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || !draft.isValid)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 560)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let model = draft.toModel(merging: original)
        let success = await onSave(model)
        if success {
            dismiss()
        } else {
            error = "Save failed."
        }
    }
}

private struct FileDraft {
    var name: String = ""
    var displayName: String = ""
    var type: String = ""
    var source: String = "remote"
    var urls: [String] = []
    var content: String = ""
    var ua: String = ""
    var proxy: String = ""

    init(model: SubStoreFile?) {
        guard let model else { return }
        self.name = model.name
        self.displayName = model.displayName ?? ""
        self.type = model.type ?? ""
        self.source = model.source ?? "remote"
        self.urls = SubscriptionDraft.splitURLs(model.url)
        self.content = model.content ?? ""
        self.ua = model.ua ?? ""
        self.proxy = model.proxy ?? ""
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toModel(merging original: SubStoreFile?) -> SubStoreFile {
        var model = original ?? SubStoreFile(name: name)
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.displayName = displayName.trimmedNilIfEmpty
        model.type = type.trimmedNilIfEmpty
        model.source = source
        model.url = SubscriptionDraft.joinURLs(urls)
        model.content = content.trimmedNilIfEmpty
        model.ua = ua.trimmedNilIfEmpty
        model.proxy = proxy.trimmedNilIfEmpty
        return model
    }
}

// MARK: - Modules section

struct SubStoreModulesSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var editing: SubStoreModule?

    var body: some View {
        @Bindable var subStore = subStore
        HStack(spacing: 0) {
            list(selection: $subStore.selection)
                .frame(width: 320)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editing) { module in
            ModuleEditorSheet(module: module) { updatedContent in
                await subStore.saveModule(name: module.name, content: updatedContent)
            }
        }
    }

    private func list(selection: Binding<SubStoreStore.Selection?>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.modules.count) modules")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await subStore.refreshModules() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh modules")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: selection) {
                ForEach(subStore.modules) { module in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.name)
                            .font(.headline)
                        if let description = module.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .tag(SubStoreStore.Selection.module(module.name))
                    .contextMenu {
                        Button("Edit…") { editing = module }
                        Divider()
                        Button("Delete", role: .destructive) {
                            Task { await subStore.deleteModule(name: module.name) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .module(let name) = subStore.selection,
           let module = subStore.modules.first(where: { $0.name == name }) {
            ModuleDetail(module: module, onEdit: { editing = module })
        } else {
            ContentUnavailableView("Select a module", systemImage: "curlybraces")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ModuleDetail: View {
    @Environment(SubStoreStore.self) private var subStore
    let module: SubStoreModule
    let onEdit: () -> Void
    @State private var deleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(module.name)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { deleting = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding(20)
            Divider()
            ScrollView {
                Text(module.content.isEmpty ? "(empty module)" : module.content)
                    .font(.body.monospaced())
                    .padding(16)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Delete \(module.name)?", isPresented: $deleting) {
            Button("Delete Permanently", role: .destructive) {
                Task { await subStore.deleteModule(name: module.name) }
                deleting = false
            }
            Button("Cancel", role: .cancel) { deleting = false }
        }
    }
}

private struct ModuleEditorSheet: View {
    let module: SubStoreModule
    let onSave: (String) async -> Bool

    @State private var content: String
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(module: SubStoreModule, onSave: @escaping (String) async -> Bool) {
        self.module = module
        self.onSave = onSave
        self._content = State(initialValue: module.content)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $content)
                    .font(.body.monospaced())
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .navigationTitle("Edit Module: \(module.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 540)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let success = await onSave(content)
        if success {
            dismiss()
        } else {
            error = "Save failed."
        }
    }
}

// MARK: - Helpers

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

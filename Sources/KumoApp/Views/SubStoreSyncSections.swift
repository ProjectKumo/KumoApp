import SwiftUI
import KumoCoreKit

// MARK: - Artifacts

struct SubStoreArtifactsSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var editing: SubStoreArtifact?
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
            ArtifactEditorSheet(original: nil) { draft in
                await subStore.saveArtifact(name: nil, draft: draft)
            }
        }
        .sheet(item: $editing) { artifact in
            ArtifactEditorSheet(original: artifact) { draft in
                await subStore.saveArtifact(name: artifact.name, draft: draft)
            }
        }
    }

    private func list(selection: Binding<SubStoreStore.Selection?>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.artifacts.count) artifacts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { creatingNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New artifact")
                Button {
                    Task { await subStore.syncAllArtifacts() }
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Sync all artifacts")
                Button {
                    Task { await subStore.refreshArtifacts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh artifacts")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: selection) {
                ForEach(subStore.artifacts) { artifact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.resolvedDisplayName)
                            .font(.headline)
                        Text("\(artifact.type) · \(artifact.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SubStoreStore.Selection.artifact(artifact.name))
                    .contextMenu {
                        Button("Edit…") { editing = artifact }
                        Button("Sync") {
                            Task { await subStore.syncArtifact(name: artifact.name) }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            Task { await subStore.deleteArtifact(name: artifact.name) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .artifact(let name) = subStore.selection,
           let artifact = subStore.artifacts.first(where: { $0.name == name }) {
            ArtifactDetail(artifact: artifact, onEdit: { editing = artifact })
        } else {
            ContentUnavailableView("Select an artifact", systemImage: "shippingbox")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ArtifactDetail: View {
    @Environment(SubStoreStore.self) private var subStore
    let artifact: SubStoreArtifact
    let onEdit: () -> Void
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(artifact.resolvedDisplayName)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    Button {
                        Task { await subStore.syncArtifact(name: artifact.name) }
                    } label: {
                        Label("Sync", systemImage: "icloud.and.arrow.up")
                    }
                    Button(role: .destructive) { deleting = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledRow(label: "Type", value: artifact.type)
                        LabeledRow(label: "Source", value: artifact.source)
                        if let platform = artifact.platform, !platform.isEmpty {
                            LabeledRow(label: "Platform", value: platform)
                        }
                        if let sync = artifact.sync {
                            LabeledRow(label: "Auto Sync", value: sync ? "Yes" : "No")
                        }
                        if let url = artifact.url, !url.isEmpty {
                            LabeledRow(label: "URL", value: url)
                        }
                        if let updated = artifact.updated {
                            LabeledRow(label: "Updated", value: Date(timeIntervalSince1970: TimeInterval(updated)).formatted(.dateTime))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyleIfAvailable()
        .confirmationDialog("Delete \(artifact.resolvedDisplayName)?", isPresented: $deleting) {
            Button("Delete Permanently", role: .destructive) {
                Task { await subStore.deleteArtifact(name: artifact.name) }
                deleting = false
            }
            Button("Cancel", role: .cancel) { deleting = false }
        }
    }
}

private struct ArtifactEditorSheet: View {
    let original: SubStoreArtifact?
    let onSave: (SubStoreArtifact) async -> Bool

    @State private var draft: ArtifactDraft
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(original: SubStoreArtifact?, onSave: @escaping (SubStoreArtifact) async -> Bool) {
        self.original = original
        self.onSave = onSave
        self._draft = State(initialValue: ArtifactDraft(model: original))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $draft.name)
                    TextField("Display Name", text: $draft.displayName)
                    Picker("Type", selection: $draft.type) {
                        Text("Subscription").tag("subscription")
                        Text("Collection").tag("collection")
                        Text("File").tag("file")
                    }
                    TextField("Source", text: $draft.source, prompt: Text("Sub or collection name"))
                    TextField("Platform", text: $draft.platform, prompt: Text("e.g. ClashMeta, Surge"))
                    Toggle("Auto Sync", isOn: $draft.sync)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(original == nil ? "New Artifact" : "Edit \(original?.resolvedDisplayName ?? "")")
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
        .frame(minWidth: 520, minHeight: 420)
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

private struct ArtifactDraft {
    var name: String = ""
    var displayName: String = ""
    var type: String = "subscription"
    var source: String = ""
    var platform: String = "ClashMeta"
    var sync: Bool = true

    init(model: SubStoreArtifact?) {
        guard let model else { return }
        self.name = model.name
        self.displayName = model.displayName ?? ""
        self.type = model.type
        self.source = model.source
        self.platform = model.platform ?? "ClashMeta"
        self.sync = model.sync ?? true
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toModel(merging original: SubStoreArtifact?) -> SubStoreArtifact {
        var model = original ?? SubStoreArtifact(name: name, type: type, source: source)
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.displayName = displayName.isEmpty ? nil : displayName
        model.type = type
        model.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        model.platform = platform.isEmpty ? nil : platform
        model.sync = sync
        return model
    }
}

// MARK: - Archives

struct SubStoreArchivesSection: View {
    @Environment(SubStoreStore.self) private var subStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.archives.count) archived items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await subStore.refreshArchives() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh archives")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if subStore.archives.isEmpty {
                ContentUnavailableView("No archives", systemImage: "archivebox", description: Text("Items deleted with “Move to Archive” show up here for restore."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(subStore.archives) { archive in
                        HStack {
                            Image(systemName: archive.type == "collection" ? "square.stack.3d.up" : "rectangle.stack")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(archive.name)
                                    .font(.headline)
                                if let time = archive.time {
                                    Text(Date(timeIntervalSince1970: TimeInterval(time)).formatted(.dateTime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Restore") {
                                Task { await subStore.restoreArchive(archive) }
                            }
                            Button(role: .destructive) {
                                Task { await subStore.deleteArchive(archive) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Tokens

struct SubStoreTokensSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var creatingToken = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.tokens.count) tokens")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { creatingToken = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New share token")
                Button {
                    Task { await subStore.refreshTokens() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh tokens")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if subStore.tokens.isEmpty {
                ContentUnavailableView("No share tokens", systemImage: "key", description: Text("Share tokens grant temporary read-only links to subscriptions and collections."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(subStore.tokens) { token in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(token.type)/\(token.name)")
                                    .font(.headline)
                                Text(token.token)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let exp = token.exp {
                                    Text("Expires \(Date(timeIntervalSince1970: TimeInterval(exp)).formatted(.dateTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No expiration")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await subStore.deleteToken(token: token.token) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $creatingToken) {
            TokenCreationSheet { type, name, expiresAt in
                await subStore.createToken(type: type, name: name, expiresAt: expiresAt)
            }
        }
    }
}

private struct TokenCreationSheet: View {
    let onCreate: (String, String, Int64?) async -> Void
    @State private var type: String = "sub"
    @State private var name: String = ""
    @State private var setExpiry: Bool = false
    @State private var expiry: Date = Date().addingTimeInterval(86400 * 30)
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    Text("Subscription").tag("sub")
                    Text("Collection").tag("collection")
                    Text("File").tag("file")
                }
                TextField("Name", text: $name)
                Toggle("Set expiration", isOn: $setExpiry)
                if setExpiry {
                    DatePicker("Expires", selection: $expiry)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Share Token")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            let timestamp = setExpiry ? Int64(expiry.timeIntervalSince1970 * 1000) : nil
                            await onCreate(type, name.trimmingCharacters(in: .whitespacesAndNewlines), timestamp)
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

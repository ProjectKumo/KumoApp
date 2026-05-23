import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct ProfilesView: View {
    @Environment(KumoAppStore.self) private var store
    @State private var remoteURL = ""
    @State private var usesProxyForImport = false
    @State private var isImportingFile = false
    @State private var editingProfile: ProfileEditDraft?
    @State private var deletingProfile: ProfileSummary?
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        KumoPage(title: "Profiles") {
            VStack(alignment: .leading, spacing: 14) {
                importControls

                if store.profiles.isEmpty {
                    KumoEmptyState(
                        title: "Import a profile to start",
                        systemImage: "rectangle.stack.badge.plus",
                        message: "Use a subscription URL or local YAML."
                    ) {
                        Button(String(localized: "Choose File")) {
                            isImportingFile = true
                        }
                    }
                } else {
                    List(store.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            onEdit: { openEditor(for: profile) },
                            onDelete: { deletingProfile = profile }
                        )
                    }
                    .scrollEdgeEffectStyleIfAvailable()
                }
            }
        }
        .sheet(item: $editingProfile) { draft in
            ProfileEditorSheet(draft: draft, isSaving: store.isLoading) { editedDraft in
                await store.updateProfile(
                    id: editedDraft.id,
                    name: editedDraft.name,
                    remoteURLString: editedDraft.remoteURLString,
                    autoUpdate: editedDraft.autoUpdate,
                    useProxy: editedDraft.useProxy,
                    rawYAML: editedDraft.rawYAML
                )
                if store.errorMessage == nil {
                    editingProfile = nil
                }
            } onCancel: {
                editingProfile = nil
            }
        }
        .confirmationDialog(String(localized: "Delete Profile?"),
            isPresented: Binding {
                deletingProfile != nil
            } set: { isPresented in
                if !isPresented {
                    deletingProfile = nil
                }
            },
            presenting: deletingProfile
        ) { profile in
            Button(String(localized: "Delete \(profile.name)"), role: .destructive) {
                Task {
                    await store.deleteProfile(profile)
                    deletingProfile = nil
                }
            }
            .disabled(profile.id == "default")
            Button(String(localized: "Cancel"), role: .cancel) {
                deletingProfile = nil
            }
        } message: { profile in
            Text(profile.isCurrent ? "Kumo will switch to another profile and restart the running core." : "This removes the local YAML and saved profile metadata.")
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            let hasAccess = url.startAccessingSecurityScopedResource()
            Task {
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                await store.importLocalProfile(from: url)
            }
        }
        .task {
            store.refreshProfiles()
        }
        .onAppear {
            urlFieldFocused = true
        }
    }

    private var importControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                subscriptionURLField
                proxyImportToggle
                importActionGroup
            }

            VStack(alignment: .leading, spacing: 8) {
                subscriptionURLField
                HStack(spacing: 8) {
                    proxyImportToggle
                    Spacer()
                    importActionGroup
                }
            }
        }
    }

    private var subscriptionURLField: some View {
        TextField("Subscription URL", text: $remoteURL)
            .textFieldStyle(.roundedBorder)
            .focused($urlFieldFocused)
            .onSubmit { importRemoteProfile() }
    }

    private var proxyImportToggle: some View {
        Toggle(String(localized: "Use Kumo to fetch"), isOn: $usesProxyForImport)
            .toggleStyle(.checkbox)
            .fixedSize()
    }

    private var importActionGroup: some View {
        HStack(spacing: 8) {
            PasteButton(payloadType: String.self) { values in
                if let value = values.first {
                    remoteURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .labelStyle(.iconOnly)
            .help(String(localized: "Paste subscription URL"))
            .accessibilityLabel(String(localized: "Paste subscription URL"))

            Button(String(localized: "Import URL")) {
                importRemoteProfile()
            }
            .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isImportingProfile)

            Button(String(localized: "Import File…")) {
                isImportingFile = true
            }

            subStoreImportMenu
        }
    }

    private var subStoreImportMenu: some View {
        Menu {
            Button(String(localized: "Reload Items")) {
                Task { await store.loadSubStoreEntries() }
            }
            if store.subStoreEntries.isEmpty {
                Text(store.subStoreRuntimeStatus.backendURL == nil
                     ? "Start Sub-Store to load items"
                     : "No items loaded yet")
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                ForEach(store.subStoreEntries) { entry in
                    Button(entry.resolvedDisplayName) {
                        Task {
                            await store.importSubStoreProfile(
                                path: entry.downloadPath,
                                name: entry.resolvedDisplayName,
                                useProxy: usesProxyForImport
                            )
                        }
                    }
                }
            }
        } label: {
            Label(String(localized: "From Sub-Store"), systemImage: "square.stack.3d.up")
        }
        .menuStyle(.button)
        .help(String(localized: "Import a profile from the local Sub-Store"))
        .disabled(store.subStoreRuntimeStatus.backendURL == nil)
    }

    private func importRemoteProfile() {
        let value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await store.importRemoteProfile(urlString: value, useProxy: usesProxyForImport)
            if store.errorMessage == nil {
                remoteURL = ""
            }
        }
    }

    private func openEditor(for profile: ProfileSummary) {
        guard let rawYAML = store.profileContent(id: profile.id) else {
            return
        }

        editingProfile = ProfileEditDraft(
            id: profile.id,
            name: profile.name,
            kind: profile.kind,
            remoteURLString: profile.remoteURL?.absoluteString ?? "",
            autoUpdate: profile.autoUpdate,
            useProxy: profile.useProxy,
            rawYAML: rawYAML
        )
    }
}

private struct ProfileRow: View {
    @Environment(KumoAppStore.self) private var store
    let profile: ProfileSummary
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isCurrent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(profile.isCurrent ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.headline)
                    if profile.kind == .remote {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(profile.autoUpdate ? .secondary : .tertiary)
                            .help(profile.autoUpdate ? "Auto update enabled" : "Auto update disabled")
                    }
                    if profile.isSubStoreManaged {
                        Text(String(localized: "Sub-Store"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .kumoSubtleBackground(in: .capsule)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let usageText {
                    Text(usageText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let updatedAt = profile.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !profile.isCurrent {
                Button(String(localized: "Use")) {
                    Task { await store.selectProfile(profile) }
                }
                .disabled(store.isLoading)
            }
            Menu {
                Button(String(localized: "Edit")) {
                    onEdit()
                }
                if let homeURL = profile.homeURL {
                    Link(String(localized: "Open Home Page"), destination: homeURL)
                }
                Divider()
                Button(String(localized: "Delete"), role: .destructive) {
                    onDelete()
                }
                .disabled(profile.id == "default")
            } label: {
                Label(String(localized: "More"), systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(String(localized: "Use Profile")) {
                Task { await store.selectProfile(profile) }
            }
            .disabled(profile.isCurrent)
            Button(String(localized: "Edit Profile")) {
                onEdit()
            }
            if profile.kind == .remote {
                Button(String(localized: "Refresh Profile")) {
                    Task { await store.refreshProfile(profile) }
                }
            }
            Button(String(localized: "Delete Profile"), role: .destructive) {
                onDelete()
            }
            .disabled(profile.id == "default")
        }
    }

    private var subtitle: String {
        if let remoteURL = profile.remoteURL {
            return remoteURL.absoluteString
        }
        return profile.sourceDescription
    }

    private var usageText: String? {
        guard let info = profile.subscriptionUserInfo, info.total > 0 else {
            return nil
        }
        let used = info.upload + info.download
        let expireText = info.expire
            .map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .abbreviated, time: .omitted) }
            ?? "No expiry"
        return "\(used.kumoByteCount) / \(info.total.kumoByteCount) · \(expireText)"
    }
}

private struct ProfileEditDraft: Identifiable {
    let id: String
    var name: String
    var kind: ProfileKind
    var remoteURLString: String
    var autoUpdate: Bool
    var useProxy: Bool
    var rawYAML: String
}

private struct ProfileEditorSheet: View {
    @State private var draft: ProfileEditDraft
    let isSaving: Bool
    let onSave: (ProfileEditDraft) async -> Void
    let onCancel: () -> Void

    init(
        draft: ProfileEditDraft,
        isSaving: Bool,
        onSave: @escaping (ProfileEditDraft) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.isSaving = isSaving
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Edit Profile"))
                .font(.title2.weight(.semibold))
                .padding(.horizontal)
                .padding(.top)

            Form {
                Section(String(localized: "Profile Info")) {
                    TextField("Name", text: $draft.name)
                    if draft.kind == .remote {
                        TextField("Subscription URL", text: $draft.remoteURLString)
                        Toggle(String(localized: "Auto Update"), isOn: $draft.autoUpdate)
                        Toggle(String(localized: "Use Proxy When Updating"), isOn: $draft.useProxy)
                    }
                }

                Section(String(localized: "YAML")) {
                    TextEditor(text: $draft.rawYAML)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 320)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    onCancel()
                }
                Button {
                    Task {
                        await onSave(draft)
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "Save"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 640, minHeight: 560)
    }
}

import SwiftUI
import KumoCoreKit

// MARK: - Subscription editor

struct SubscriptionEditorSheet: View {
    let original: SubStoreSubscription?
    let onSave: (SubStoreSubscription) async -> Bool

    @State private var draft: SubscriptionDraft
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(original: SubStoreSubscription?, onSave: @escaping (SubStoreSubscription) async -> Bool) {
        self.original = original
        self.onSave = onSave
        self._draft = State(initialValue: SubscriptionDraft(model: original))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $draft.name)
                    TextField("Display Name", text: $draft.displayName)
                    TextField("Icon URL", text: $draft.icon)
                    Picker("Source", selection: $draft.source) {
                        Text("Remote").tag(SubscriptionDraft.Source.remote)
                        Text("Local").tag(SubscriptionDraft.Source.local)
                    }
                    .pickerStyle(.segmented)
                }

                if draft.source == .remote {
                    Section("Remote") {
                        TextField("Subscription URL (one per line)", text: $draft.url, axis: .vertical)
                            .lineLimit(3...10)
                            .font(.body.monospaced())
                        TextField("User-Agent", text: $draft.ua, prompt: Text("Optional"))
                        Picker("Merge Sources", selection: $draft.mergeSources) {
                            ForEach(SubscriptionDraft.MergeMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        TextField("Subscription Userinfo", text: $draft.subUserinfo, prompt: Text("Optional"))
                    }
                }

                if draft.source == .local || draft.mergeSources != .none {
                    Section("Local Content") {
                        TextEditor(text: $draft.content)
                            .font(.body.monospaced())
                            .frame(minHeight: 160)
                    }
                }

                Section("Behavior") {
                    TextField("Proxy (Clash node name)", text: $draft.proxy, prompt: Text("Optional"))
                    Picker("Ignore Failed Remote", selection: $draft.ignoreFailedRemoteSub) {
                        ForEach(SubscriptionDraft.IgnoreMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    TextField("Tags (comma separated)", text: $draft.tagsCSV)
                }

                Section {
                    ProcessPipelineEditor(pipeline: $draft.process)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(original == nil ? "New Subscription" : "Edit \(original?.resolvedDisplayName ?? "")")
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
        .frame(minWidth: 560, minHeight: 600)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let model = draft.toModel(merging: original)
        let success = await onSave(model)
        if success {
            dismiss()
        } else {
            error = "Save failed. Inspect Sub-Store logs for details."
        }
    }
}

struct SubscriptionDraft {
    enum Source: String, CaseIterable, Identifiable {
        case remote, local
        var id: String { rawValue }
    }

    enum MergeMode: String, CaseIterable, Identifiable {
        case none = ""
        case localFirst = "localFirst"
        case remoteFirst = "remoteFirst"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "Remote only"
            case .localFirst: "Local first, then remote"
            case .remoteFirst: "Remote first, then local"
            }
        }
    }

    enum IgnoreMode: String, CaseIterable, Identifiable {
        case off = ""
        case enabled = "enabled"
        case disabled = "disabled"
        case quietly = "quietly"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Default"
            case .enabled: "Enabled (notify)"
            case .disabled: "Disabled"
            case .quietly: "Enabled (quietly)"
            }
        }
    }

    var name: String = ""
    var displayName: String = ""
    var icon: String = ""
    var source: Source = .remote
    var url: String = ""
    var content: String = ""
    var ua: String = ""
    var proxy: String = ""
    var tagsCSV: String = ""
    var mergeSources: MergeMode = .none
    var subUserinfo: String = ""
    var ignoreFailedRemoteSub: IgnoreMode = .off
    var process: [JSONValue] = []

    init(model: SubStoreSubscription?) {
        guard let model else { return }
        self.name = model.name
        self.displayName = model.displayName ?? ""
        self.icon = model.icon ?? ""
        self.source = model.source == "local" ? .local : .remote
        self.url = model.url ?? ""
        self.content = model.content ?? ""
        self.ua = model.ua ?? ""
        self.proxy = model.proxy ?? ""
        self.tagsCSV = (model.tag ?? []).joined(separator: ", ")
        self.mergeSources = MergeMode(rawValue: model.mergeSources ?? "") ?? .none
        self.subUserinfo = model.subUserinfo ?? ""
        self.ignoreFailedRemoteSub = IgnoreMode(rawValue: model.ignoreFailedRemoteSub ?? "") ?? .off
        self.process = model.process ?? []
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var tagList: [String]? {
        let trimmed = tagsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return trimmed.isEmpty ? nil : trimmed
    }

    func toModel(merging original: SubStoreSubscription?) -> SubStoreSubscription {
        var model = original ?? SubStoreSubscription(name: name)
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.displayName = displayName.nilIfBlank
        model.icon = icon.nilIfBlank
        model.source = source.rawValue
        model.url = source == .local && mergeSources == .none ? nil : url.nilIfBlank
        model.content = source == .local || mergeSources != .none ? content.nilIfBlank : nil
        model.ua = ua.nilIfBlank
        model.proxy = proxy.nilIfBlank
        model.tag = tagList
        model.mergeSources = mergeSources == .none ? nil : mergeSources.rawValue
        model.subUserinfo = subUserinfo.nilIfBlank
        model.ignoreFailedRemoteSub = ignoreFailedRemoteSub == .off ? nil : ignoreFailedRemoteSub.rawValue
        model.process = process.isEmpty ? nil : process
        return model
    }
}

// MARK: - Collection editor

struct CollectionEditorSheet: View {
    let original: SubStoreCollection?
    let availableSubscriptions: [SubStoreSubscription]
    let onSave: (SubStoreCollection) async -> Bool

    @State private var draft: CollectionDraft
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(
        original: SubStoreCollection?,
        availableSubscriptions: [SubStoreSubscription],
        onSave: @escaping (SubStoreCollection) async -> Bool
    ) {
        self.original = original
        self.availableSubscriptions = availableSubscriptions
        self.onSave = onSave
        self._draft = State(initialValue: CollectionDraft(model: original))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $draft.name)
                    TextField("Display Name", text: $draft.displayName)
                    TextField("Icon URL", text: $draft.icon)
                }

                Section("Subscriptions") {
                    ForEach(availableSubscriptions) { subscription in
                        Toggle(subscription.resolvedDisplayName, isOn: binding(for: subscription.name))
                    }
                    if availableSubscriptions.isEmpty {
                        Text("No subscriptions available yet. Create one first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Tag-based picks (comma separated)", text: $draft.subscriptionTagsCSV, prompt: Text("Optional"))
                }

                Section("Behavior") {
                    Picker("Ignore Failed Remote", selection: $draft.ignoreFailedRemoteSub) {
                        ForEach(SubscriptionDraft.IgnoreMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section {
                    ProcessPipelineEditor(pipeline: $draft.process)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(original == nil ? "New Collection" : "Edit \(original?.resolvedDisplayName ?? "")")
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
        .frame(minWidth: 540, minHeight: 520)
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding {
            draft.subscriptionsSet.contains(name)
        } set: { newValue in
            if newValue {
                draft.subscriptionsSet.insert(name)
            } else {
                draft.subscriptionsSet.remove(name)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let model = draft.toModel(merging: original, knownNames: availableSubscriptions.map(\.name))
        let success = await onSave(model)
        if success {
            dismiss()
        } else {
            error = "Save failed. Inspect Sub-Store logs for details."
        }
    }
}

struct CollectionDraft {
    var name: String = ""
    var displayName: String = ""
    var icon: String = ""
    var subscriptionsSet: Set<String> = []
    var subscriptionTagsCSV: String = ""
    var ignoreFailedRemoteSub: SubscriptionDraft.IgnoreMode = .off
    var process: [JSONValue] = []

    init(model: SubStoreCollection?) {
        guard let model else { return }
        self.name = model.name
        self.displayName = model.displayName ?? ""
        self.icon = model.icon ?? ""
        self.subscriptionsSet = Set(model.subscriptions)
        self.subscriptionTagsCSV = (model.subscriptionTags ?? []).joined(separator: ", ")
        self.ignoreFailedRemoteSub = SubscriptionDraft.IgnoreMode(rawValue: model.ignoreFailedRemoteSub ?? "") ?? .off
        self.process = model.process ?? []
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var tagList: [String]? {
        let trimmed = subscriptionTagsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return trimmed.isEmpty ? nil : trimmed
    }

    func toModel(merging original: SubStoreCollection?, knownNames: [String]) -> SubStoreCollection {
        var model = original ?? SubStoreCollection(name: name)
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.displayName = displayName.nilIfBlank
        model.icon = icon.nilIfBlank
        model.subscriptions = knownNames.filter { subscriptionsSet.contains($0) }
        model.subscriptionTags = tagList
        model.ignoreFailedRemoteSub = ignoreFailedRemoteSub == .off ? nil : ignoreFailedRemoteSub.rawValue
        model.process = process.isEmpty ? nil : process
        return model
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

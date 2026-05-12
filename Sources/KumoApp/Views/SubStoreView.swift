import AppKit
import SwiftUI
import KumoCoreKit

struct SubStoreView: View {
    @Environment(KumoAppStore.self) private var appStore
    @Environment(SubStoreStore.self) private var subStore
    @State private var primary: PrimarySection = .subscriptions
    @State private var advancedScreen: AdvancedScreen?
    @State private var showsServerSettings = false

    var body: some View {
        Group {
            if isBackendAvailable {
                PrimaryWorkspace(
                    primary: $primary,
                    advancedScreen: $advancedScreen,
                    showsServerSettings: $showsServerSettings
                )
            } else {
                SubStoreEmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await appStore.refreshSubStoreRuntimeStatus()
            if isBackendAvailable {
                await subStore.refreshSubscriptions()
                await subStore.refreshCollections()
            }
        }
        .onChange(of: primary) { _, newValue in
            subStore.section = newValue == .subscriptions ? .subscriptions : .collections
            Task {
                switch newValue {
                case .subscriptions: await subStore.refreshSubscriptions()
                case .collections: await subStore.refreshCollections()
                }
            }
        }
        .onChange(of: appStore.subStoreRuntimeStatus.isBackendRunning) { _, running in
            guard running else { return }
            Task {
                await subStore.refreshSubscriptions()
                await subStore.refreshCollections()
            }
        }
        .sheet(item: $advancedScreen) { screen in
            AdvancedScreenSheet(screen: screen)
        }
    }

    private var isBackendAvailable: Bool {
        appStore.subStoreRuntimeStatus.backendURL != nil || appStore.subStoreStatus.usesCustomBackend
    }
}

// MARK: - Section model

enum PrimarySection: Hashable {
    case subscriptions
    case collections

    var label: String {
        switch self {
        case .subscriptions: "Subscriptions"
        case .collections: "Collections"
        }
    }
}

enum AdvancedScreen: String, Identifiable, CaseIterable {
    case files
    case modules
    case artifacts
    case archives
    case tokens
    case settings
    case logs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .files: "Files"
        case .modules: "Modules"
        case .artifacts: "Artifacts"
        case .archives: "Archives"
        case .tokens: "Share Tokens"
        case .settings: "Server Settings"
        case .logs: "Backend Logs"
        }
    }

    var symbol: String {
        switch self {
        case .files: "doc.text"
        case .modules: "curlybraces"
        case .artifacts: "shippingbox"
        case .archives: "archivebox"
        case .tokens: "key"
        case .settings: "slider.horizontal.3"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}

// MARK: - Primary workspace

private struct PrimaryWorkspace: View {
    @Environment(KumoAppStore.self) private var appStore
    @Environment(SubStoreStore.self) private var subStore
    @Binding var primary: PrimarySection
    @Binding var advancedScreen: AdvancedScreen?
    @Binding var showsServerSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let banner = errorBanner {
                BackendBanner(text: banner) {
                    Task { await appStore.refreshSubStoreRuntimeStatus() }
                }
                Divider()
            }
            primaryToolbar
            Divider()
            primaryContent
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch primary {
        case .subscriptions: SubscriptionsSection()
        case .collections: CollectionsSection()
        }
    }

    private var primaryToolbar: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $primary) {
                Text(PrimarySection.subscriptions.label).tag(PrimarySection.subscriptions)
                Text(PrimarySection.collections.label).tag(PrimarySection.collections)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)

            if subStore.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Menu {
                Section("Advanced") {
                    ForEach(AdvancedScreen.allCases) { screen in
                        Button {
                            advancedScreen = screen
                        } label: {
                            Label(screen.label, systemImage: screen.symbol)
                        }
                    }
                }
                Divider()
                Button {
                    Task { await appStore.restartSubStoreService() }
                } label: {
                    Label("Restart Backend", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!appStore.subStoreStatus.isEnabled || appStore.isLoading)
                Button {
                    Task { await appStore.setSubStoreEnabled(false) }
                } label: {
                    Label("Stop Backend", systemImage: "stop.fill")
                }
                .disabled(!appStore.subStoreStatus.isEnabled || appStore.isLoading)
                Divider()
                Button {
                    NSWorkspace.shared.open(appStore.subStoreLogURL)
                } label: {
                    Label("Open Backend Log…", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Sub-Store actions")
            .accessibilityLabel("More Sub-Store actions")

            Button {
                showsServerSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Backend connection settings")
            .accessibilityLabel("Backend connection settings")
            .popover(isPresented: $showsServerSettings, arrowEdge: .bottom) {
                SubStoreServerSettingsPopover()
                    .frame(width: 380)
            }
        }
        .imageScale(.large)
    }

    private var errorBanner: String? {
        appStore.subStoreStatus.lastError
    }
}

// MARK: - Backend error banner

private struct BackendBanner: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.08))
    }
}

// MARK: - Empty state when no backend

private struct SubStoreEmptyState: View {
    @Environment(KumoAppStore.self) private var appStore

    private enum Mode {
        case noResources
        case starting
        case stopped
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "square.stack.3d.up")
        } description: {
            Text(message)
        } actions: {
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var actions: some View {
        switch mode {
        case .noResources:
            Button("Prepare Resources") {
                appStore.prepareSubStoreResources()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appStore.isLoading)
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("Refresh") {
                    Task { await appStore.refreshSubStoreRuntimeStatus() }
                }
            }
        case .stopped:
            Button("Start Sub-Store") {
                Task { await appStore.setSubStoreEnabled(true) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appStore.isLoading)
        }
    }

    private var mode: Mode {
        if !appStore.subStoreRuntimeStatus.resourcesInstalled {
            return .noResources
        }
        if appStore.subStoreStatus.isEnabled {
            return .starting
        }
        return .stopped
    }

    private var title: String {
        switch mode {
        case .noResources: "Bundled Resources Not Installed"
        case .starting: "Starting Sub-Store…"
        case .stopped: "Sub-Store Is Off"
        }
    }

    private var message: String {
        switch mode {
        case .noResources:
            return "Prepare the bundled Sub-Store resources, then start the local workspace."
        case .starting:
            return "The local Sub-Store backend is launching. This usually takes a couple of seconds."
        case .stopped:
            return "Start Sub-Store to manage subscriptions and collections."
        }
    }
}

// MARK: - Advanced sheet

private struct AdvancedScreenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubStoreStore.self) private var subStore
    let screen: AdvancedScreen

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(screen.label)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(minWidth: 760, minHeight: 540)
        .task {
            await refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .files: SubStoreFilesSection()
        case .modules: SubStoreModulesSection()
        case .artifacts: SubStoreArtifactsSection()
        case .archives: SubStoreArchivesSection()
        case .tokens: SubStoreTokensSection()
        case .settings: SubStoreSettingsSection()
        case .logs: SubStoreLogsSection()
        }
    }

    private func refresh() async {
        switch screen {
        case .files: await subStore.refreshFiles()
        case .modules: await subStore.refreshModules()
        case .artifacts: await subStore.refreshArtifacts()
        case .archives: await subStore.refreshArchives()
        case .tokens: await subStore.refreshTokens()
        case .settings: await subStore.refreshSettings()
        case .logs: await subStore.refreshLogs()
        }
    }
}

// MARK: - Subscriptions

private struct SubscriptionsSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var editingDraft: SubStoreSubscription?
    @State private var creatingNew = false

    var body: some View {
        @Bindable var subStore = subStore
        HStack(spacing: 0) {
            subscriptionList(selection: $subStore.selection)
                .frame(width: 320)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $creatingNew) {
            SubscriptionEditorSheet(original: nil) { draft in
                await subStore.saveSubscription(name: nil, draft: draft)
            }
        }
        .sheet(item: $editingDraft) { draft in
            SubscriptionEditorSheet(original: draft) { updated in
                await subStore.saveSubscription(name: draft.name, draft: updated)
            }
        }
    }

    private func subscriptionList(selection: Binding<SubStoreStore.Selection?>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.subscriptions.count) subscriptions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    creatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New subscription")
                Button {
                    Task { await subStore.refreshSubscriptions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh subscriptions")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: selection) {
                ForEach(subStore.subscriptions) { subscription in
                    SubscriptionRow(subscription: subscription)
                        .tag(SubStoreStore.Selection.subscription(subscription.name))
                        .contextMenu {
                            Button("Edit…") {
                                editingDraft = subscription
                            }
                            Button("Refresh Flow") {
                                Task { await subStore.loadFlow(for: subscription.name) }
                            }
                            Divider()
                            Button("Delete (Archive)", role: .destructive) {
                                Task { await subStore.deleteSubscription(name: subscription.name, archive: true) }
                            }
                            Button("Delete Permanently", role: .destructive) {
                                Task { await subStore.deleteSubscription(name: subscription.name, archive: false) }
                            }
                        }
                }
                .onMove { source, destination in
                    var list = subStore.subscriptions
                    list.move(fromOffsets: source, toOffset: destination)
                    Task { await subStore.reorderSubscriptions(list) }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .subscription(let name) = subStore.selection,
           let subscription = subStore.subscriptions.first(where: { $0.name == name }) {
            SubscriptionDetail(subscription: subscription, onEdit: { editingDraft = subscription })
        } else {
            ContentUnavailableView("Select a subscription", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SubscriptionRow: View {
    @Environment(SubStoreStore.self) private var subStore
    let subscription: SubStoreSubscription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: subscription.isLocal ? "doc" : "globe")
                    .foregroundStyle(.secondary)
                Text(subscription.resolvedDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let tags = subscription.tag, !tags.isEmpty {
                    Text(tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let flow = subStore.flowByName[subscription.name], flow.total > 0 {
                FlowBar(flow: flow)
            }
        }
        .padding(.vertical, 4)
        .task(id: subscription.name) {
            await subStore.loadFlow(for: subscription.name)
        }
    }
}

private struct SubscriptionDetail: View {
    @Environment(KumoAppStore.self) private var appStore
    @Environment(SubStoreStore.self) private var subStore
    let subscription: SubStoreSubscription
    let onEdit: () -> Void
    @State private var deleteConfirmation: SubscriptionDeletionDraft?
    @State private var importInProgress = false
    @State private var previewTarget: PreviewTarget = .clashMeta

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                detailsCard
                if let flow = subStore.flowByName[subscription.name], flow.total > 0 {
                    FlowCard(flow: flow)
                }
                preview
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyleIfAvailable()
        .confirmationDialog(
            "Delete \(subscription.resolvedDisplayName)?",
            isPresented: deletionBinding,
            presenting: deleteConfirmation
        ) { draft in
            Button("Move to Archive", role: .destructive) {
                Task {
                    await subStore.deleteSubscription(name: draft.name, archive: true)
                    deleteConfirmation = nil
                }
            }
            Button("Delete Permanently", role: .destructive) {
                Task {
                    await subStore.deleteSubscription(name: draft.name, archive: false)
                    deleteConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmation = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(subscription.resolvedDisplayName)
                    .font(.title2.weight(.semibold))
                Text(subscription.isLocal ? "Local" : "Remote")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .kumoSubtleBackground(in: .capsule)
            }
            if subscription.displayName != nil, subscription.displayName != subscription.name {
                Text(subscription.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button("Refresh Flow") {
                Task { await subStore.loadFlow(for: subscription.name) }
            }
            .disabled(subStore.isFetchingFlow.contains(subscription.name))

            Picker("Target", selection: $previewTarget) {
                ForEach(PreviewTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 140)

            Button {
                Task { await subStore.previewSubscription(subscription, target: previewTarget.rawValue) }
            } label: {
                if subStore.isPreviewing.contains(subscription.name) {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Preview Nodes")
                }
            }
            .disabled(subStore.isPreviewing.contains(subscription.name))

            Button {
                Task {
                    importInProgress = true
                    await appStore.importSubStoreProfile(
                        path: subscription.downloadPath,
                        name: subscription.resolvedDisplayName,
                        useProxy: false
                    )
                    importInProgress = false
                }
            } label: {
                if importInProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Import to Kumo")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(importInProgress)

            Spacer()

            Button(role: .destructive) {
                deleteConfirmation = SubscriptionDeletionDraft(name: subscription.name)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var detailsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                LabeledRow(label: "Source", value: subscription.source ?? "remote")
                if !subscription.urlList.isEmpty {
                    LabeledRow(label: "URLs", value: subscription.urlList.joined(separator: "\n"))
                }
                if let ua = subscription.ua, !ua.isEmpty {
                    LabeledRow(label: "User-Agent", value: ua)
                }
                if let proxy = subscription.proxy, !proxy.isEmpty {
                    LabeledRow(label: "Proxy", value: proxy)
                }
                if let mergeSources = subscription.mergeSources, !mergeSources.isEmpty {
                    LabeledRow(label: "Merge Sources", value: mergeSources)
                }
                if let ignore = subscription.ignoreFailedRemoteSub, !ignore.isEmpty {
                    LabeledRow(label: "Ignore Failed", value: ignore)
                }
                if let tags = subscription.tag, !tags.isEmpty {
                    LabeledRow(label: "Tags", value: tags.joined(separator: ", "))
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let result = subStore.previewBySubscription[subscription.name] {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original: \(result.original.count) nodes  |  Processed: \(result.processed.count) nodes")
                        .font(.callout.weight(.medium))
                    if let firstFew = previewSummary(from: result.processed.isEmpty ? result.original : result.processed) {
                        Text(firstFew)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("Preview Nodes", systemImage: "eye")
            }
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding {
            deleteConfirmation != nil
        } set: { newValue in
            if !newValue { deleteConfirmation = nil }
        }
    }

    private func previewSummary(from values: [JSONValue]) -> String? {
        guard !values.isEmpty else { return nil }
        let names = values.prefix(20).compactMap { value -> String? in
            value.objectValue?["name"]?.stringValue
        }
        var lines = names
        if values.count > 20 {
            lines.append("… and \(values.count - 20) more")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private struct SubscriptionDeletionDraft: Identifiable {
    var name: String
    var id: String { name }
}

// MARK: - Collections

private struct CollectionsSection: View {
    @Environment(SubStoreStore.self) private var subStore
    @State private var editingDraft: SubStoreCollection?
    @State private var creatingNew = false

    var body: some View {
        @Bindable var subStore = subStore
        HStack(spacing: 0) {
            collectionList(selection: $subStore.selection)
                .frame(width: 320)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $creatingNew) {
            CollectionEditorSheet(
                original: nil,
                availableSubscriptions: subStore.subscriptions
            ) { draft in
                await subStore.saveCollection(name: nil, draft: draft)
            }
        }
        .sheet(item: $editingDraft) { draft in
            CollectionEditorSheet(
                original: draft,
                availableSubscriptions: subStore.subscriptions
            ) { updated in
                await subStore.saveCollection(name: draft.name, draft: updated)
            }
        }
    }

    private func collectionList(selection: Binding<SubStoreStore.Selection?>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(subStore.collections.count) collections")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    creatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New collection")
                Button {
                    Task { await subStore.refreshCollections() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh collections")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List(selection: selection) {
                ForEach(subStore.collections) { collection in
                    CollectionRow(collection: collection)
                        .tag(SubStoreStore.Selection.collection(collection.name))
                        .contextMenu {
                            Button("Edit…") { editingDraft = collection }
                            Divider()
                            Button("Delete (Archive)", role: .destructive) {
                                Task { await subStore.deleteCollection(name: collection.name, archive: true) }
                            }
                            Button("Delete Permanently", role: .destructive) {
                                Task { await subStore.deleteCollection(name: collection.name, archive: false) }
                            }
                        }
                }
                .onMove { source, destination in
                    var list = subStore.collections
                    list.move(fromOffsets: source, toOffset: destination)
                    Task { await subStore.reorderCollections(list) }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .collection(let name) = subStore.selection,
           let collection = subStore.collections.first(where: { $0.name == name }) {
            CollectionDetail(collection: collection, onEdit: { editingDraft = collection })
        } else {
            ContentUnavailableView("Select a collection", systemImage: "square.stack.3d.up")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CollectionRow: View {
    let collection: SubStoreCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.secondary)
                Text(collection.resolvedDisplayName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text("\(collection.subscriptions.count) subscriptions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CollectionDetail: View {
    @Environment(KumoAppStore.self) private var appStore
    @Environment(SubStoreStore.self) private var subStore
    let collection: SubStoreCollection
    let onEdit: () -> Void
    @State private var deleteConfirmation: CollectionDeletionDraft?
    @State private var importInProgress = false
    @State private var previewTarget: PreviewTarget = .clashMeta

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                detailsCard
                preview
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyleIfAvailable()
        .confirmationDialog(
            "Delete \(collection.resolvedDisplayName)?",
            isPresented: deletionBinding,
            presenting: deleteConfirmation
        ) { draft in
            Button("Move to Archive", role: .destructive) {
                Task {
                    await subStore.deleteCollection(name: draft.name, archive: true)
                    deleteConfirmation = nil
                }
            }
            Button("Delete Permanently", role: .destructive) {
                Task {
                    await subStore.deleteCollection(name: draft.name, archive: false)
                    deleteConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmation = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.resolvedDisplayName)
                .font(.title2.weight(.semibold))
            if collection.displayName != nil, collection.displayName != collection.name {
                Text(collection.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Picker("Target", selection: $previewTarget) {
                ForEach(PreviewTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 140)

            Button {
                Task { await subStore.previewCollection(collection, target: previewTarget.rawValue) }
            } label: {
                if subStore.isPreviewing.contains(collection.name) {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Preview Nodes")
                }
            }
            .disabled(subStore.isPreviewing.contains(collection.name))

            Button {
                Task {
                    importInProgress = true
                    await appStore.importSubStoreProfile(
                        path: collection.downloadPath,
                        name: collection.resolvedDisplayName,
                        useProxy: false
                    )
                    importInProgress = false
                }
            } label: {
                if importInProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Import to Kumo")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(importInProgress)

            Spacer()

            Button(role: .destructive) {
                deleteConfirmation = CollectionDeletionDraft(name: collection.name)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var detailsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if !collection.subscriptions.isEmpty {
                    LabeledRow(label: "Subscriptions", value: collection.subscriptions.joined(separator: "\n"))
                }
                if let tags = collection.subscriptionTags, !tags.isEmpty {
                    LabeledRow(label: "Subscription Tags", value: tags.joined(separator: ", "))
                }
                if let ignore = collection.ignoreFailedRemoteSub, !ignore.isEmpty {
                    LabeledRow(label: "Ignore Failed", value: ignore)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let result = subStore.previewByCollection[collection.name] {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original: \(result.original.count) nodes  |  Processed: \(result.processed.count) nodes")
                        .font(.callout.weight(.medium))
                    if let firstFew = previewSummary(from: result.processed.isEmpty ? result.original : result.processed) {
                        Text(firstFew)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("Preview Nodes", systemImage: "eye")
            }
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding {
            deleteConfirmation != nil
        } set: { newValue in
            if !newValue { deleteConfirmation = nil }
        }
    }

    private func previewSummary(from values: [JSONValue]) -> String? {
        guard !values.isEmpty else { return nil }
        let names = values.prefix(20).compactMap { value -> String? in
            value.objectValue?["name"]?.stringValue
        }
        var lines = names
        if values.count > 20 {
            lines.append("… and \(values.count - 20) more")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private struct CollectionDeletionDraft: Identifiable {
    var name: String
    var id: String { name }
}

// MARK: - Reusable widgets

private struct FlowBar: View {
    let flow: SubStoreFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: flow.usedFraction)
                .progressViewStyle(.linear)
                .tint(usageTint)
            HStack {
                Text("\(byteCount(flow.used)) / \(byteCount(flow.total))")
                Spacer()
                if let expiry = flow.expiryDate {
                    Text(expiry, style: .date)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var usageTint: Color {
        switch flow.usedFraction {
        case ..<0.7: .accentColor
        case ..<0.9: .orange
        default: .red
        }
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

private struct FlowCard: View {
    let flow: SubStoreFlow

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                FlowBar(flow: flow)
                if let days = flow.remainingDays {
                    Text("Remaining: \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Flow", systemImage: "chart.bar")
        }
    }
}

enum PreviewTarget: String, CaseIterable, Identifiable {
    case json = "JSON"
    case clash = "Clash"
    case clashMeta = "ClashMeta"
    case surge = "Surge"
    case quanX = "QX"
    case loon = "Loon"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .json: "JSON"
        case .clash: "Clash"
        case .clashMeta: "ClashMeta"
        case .surge: "Surge"
        case .quanX: "Quantumult X"
        case .loon: "Loon"
        }
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(value)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Server settings popover

private struct SubStoreServerSettingsPopover: View {
    @Environment(KumoAppStore.self) private var appStore
    @State private var draft = SubStoreServerSettingsDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use Custom Backend", isOn: $draft.usesCustomBackend)
                if draft.usesCustomBackend {
                    TextField("Backend URL", text: $draft.customBackendURL)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Allow LAN access", isOn: $draft.allowsLAN)
                    .help("Bind backend to 0.0.0.0 so other devices can reach it.")
                Toggle("Send Sub-Store requests through Kumo proxy", isOn: $draft.usesProxy)
                    .disabled(draft.usesCustomBackend)

                Divider().padding(.vertical, 4)

                cronField("Sync Cron", text: $draft.syncCron)
                cronField("Restore Cron", text: $draft.downloadCron)
                cronField("Backup Cron", text: $draft.uploadCron)
            }
            .padding(16)
            Divider()
            HStack {
                Spacer()
                Button("Reset") { sync() }
                    .disabled(draft == SubStoreServerSettingsDraft(status: appStore.subStoreStatus))
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == SubStoreServerSettingsDraft(status: appStore.subStoreStatus))
            }
            .padding(12)
        }
        .task { sync() }
    }

    private func cronField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField("Optional", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func sync() {
        draft = SubStoreServerSettingsDraft(status: appStore.subStoreStatus)
    }

    private func apply() {
        var status = appStore.subStoreStatus
        status.usesCustomBackend = draft.usesCustomBackend
        status.customBackendURL = draft.customBackendURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .flatMap(URL.init(string:))
        status.allowsLAN = draft.allowsLAN
        status.usesProxy = draft.usesProxy
        status.host = draft.allowsLAN ? "0.0.0.0" : "127.0.0.1"
        status.syncCron = draft.syncCron.trimmingCharacters(in: .whitespacesAndNewlines)
        status.downloadCron = draft.downloadCron.trimmingCharacters(in: .whitespacesAndNewlines)
        status.uploadCron = draft.uploadCron.trimmingCharacters(in: .whitespacesAndNewlines)
        appStore.updateSubStoreStatus(status)
        if status.isEnabled {
            Task { await appStore.restartSubStoreService() }
        }
    }
}

private struct SubStoreServerSettingsDraft: Equatable {
    var usesCustomBackend = false
    var customBackendURL = ""
    var allowsLAN = false
    var usesProxy = false
    var syncCron = ""
    var downloadCron = ""
    var uploadCron = ""

    init() {}

    init(status: SubStoreStatus) {
        self.usesCustomBackend = status.usesCustomBackend
        self.customBackendURL = status.customBackendURL?.absoluteString ?? ""
        self.allowsLAN = status.allowsLAN
        self.usesProxy = status.usesProxy
        self.syncCron = status.syncCron
        self.downloadCron = status.downloadCron
        self.uploadCron = status.uploadCron
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

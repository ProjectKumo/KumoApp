import SwiftUI
import UniformTypeIdentifiers
import KumoCoreKit

struct AgentSkillsView: View {
    @State private var scope: AgentSkillsScope = .global
    @State private var projectPath: String = FileManager.default.currentDirectoryPath
    @State private var isChoosingProjectFolder = false
    @State private var selectedTargets = Set(AgentSkillsTarget.allCases)
    @State private var statuses: [AgentSkillsTargetStatus] = []
    @State private var allowReplacingUntrackedSkills = false
    @State private var isBusy = false
    @State private var footerMessage: String?
    @State private var footerIsError = false

    var body: some View {
        Form {
            Section("Scope") {
                Picker("Install Scope", selection: $scope) {
                    ForEach(AgentSkillsScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if scope == .project {
                    LabeledContent("Project Folder") {
                        HStack(spacing: 8) {
                            Text(projectPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Choose Folder") {
                                isChoosingProjectFolder = true
                            }
                        }
                    }
                }
            }

            Section("Agents") {
                ForEach(AgentSkillsTarget.allCases) { target in
                    AgentSkillTargetRow(
                        target: target,
                        status: status(for: target),
                        isSelected: binding(for: target),
                        isSupported: isSupported(target)
                    )
                }
            }

            Section {
                Toggle("Replace existing non-Kumo skill directories", isOn: $allowReplacingUntrackedSkills)

                HStack {
                    Button("Refresh") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isBusy)

                    Spacer()

                    Button("Dry Run") {
                        Task { await install(dryRun: true) }
                    }
                    .disabled(isBusy || selectedSupportedTargets.isEmpty)

                    Button("Uninstall") {
                        Task { await uninstall() }
                    }
                    .disabled(isBusy || selectedSupportedTargets.isEmpty)

                    Button("Install / Update") {
                        Task { await install(dryRun: false) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || selectedSupportedTargets.isEmpty)
                }

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                if let footerMessage {
                    Text(footerMessage)
                        .font(.caption)
                        .foregroundStyle(footerIsError ? .red : .secondary)
                }
            } footer: {
                Text("Kumo installs the same bundled agent skill used by the CLI. Paths and status come from KumoCoreKit.")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .task {
            await refreshStatus()
        }
        .onChange(of: scope) { _, _ in
            selectedTargets = selectedSupportedTargets
            Task { await refreshStatus() }
        }
        .fileImporter(
            isPresented: $isChoosingProjectFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            projectPath = url.path
            Task { await refreshStatus() }
        }
    }

    private var selectedSupportedTargets: Set<AgentSkillsTarget> {
        Set(selectedTargets.filter(isSupported))
    }

    private var projectURL: URL {
        let expanded = (projectPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private func isSupported(_ target: AgentSkillsTarget) -> Bool {
        scope == .global || target.supportsProjectScope
    }

    private func status(for target: AgentSkillsTarget) -> AgentSkillsTargetStatus? {
        statuses.first { $0.target == target }
    }

    private func binding(for target: AgentSkillsTarget) -> Binding<Bool> {
        Binding {
            selectedTargets.contains(target)
        } set: { isSelected in
            if isSelected {
                selectedTargets.insert(target)
            } else {
                selectedTargets.remove(target)
            }
        }
    }

    private func refreshStatus() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let installer = try AgentSkillsInstaller()
            statuses = try installer.perTargetStatus(
                scope: scope,
                projectWorkingDirectory: projectURL
            )
            footerMessage = nil
            footerIsError = false
        } catch {
            footerMessage = displayMessage(for: error)
            footerIsError = true
        }
    }

    private func install(dryRun: Bool) async {
        await runAction {
            let installer = try AgentSkillsInstaller()
            let report = try installer.install(
                targets: selectedSupportedTargets,
                scope: scope,
                projectWorkingDirectory: projectURL,
                dryRun: dryRun,
                force: allowReplacingUntrackedSkills
            )
            return dryRun
                ? "Would install \(report.copiedSkillIds.joined(separator: ", ")) to \(report.destinationRoots.count) location(s)."
                : "Installed \(report.copiedSkillIds.joined(separator: ", ")) to \(report.destinationRoots.count) location(s)."
        }
    }

    private func uninstall() async {
        await runAction {
            let installer = try AgentSkillsInstaller()
            let report = try installer.uninstall(
                targets: selectedSupportedTargets,
                scope: scope,
                projectWorkingDirectory: projectURL,
                dryRun: false
            )
            return "Uninstalled \(report.copiedSkillIds.joined(separator: ", ")) from \(report.destinationRoots.count) location(s)."
        }
    }

    private func runAction(_ action: () throws -> String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            footerMessage = try action()
            footerIsError = false
            await refreshStatus()
        } catch {
            footerMessage = displayMessage(for: error)
            footerIsError = true
        }
    }

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private struct AgentSkillTargetRow: View {
    let target: AgentSkillsTarget
    let status: AgentSkillsTargetStatus?
    @Binding var isSelected: Bool
    let isSupported: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    AgentBrandIcon(target: target)
                    Text(target.displayName)
                    statusLabel
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .disabled(!isSupported)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if !isSupported {
            Text("Unsupported")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if status?.upToDate == true {
            Text("Up to Date")
                .font(.caption)
                .foregroundStyle(.green)
        } else if status?.installed == true {
            Text("Update Available")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text("Not Installed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detailText: String {
        guard isSupported else {
            return "This agent does not support the selected scope."
        }
        return status?.destinationRoot ?? ""
    }
}

private struct AgentBrandIcon: View {
    let target: AgentSkillsTarget

    var body: some View {
        Group {
            if let assetName = target.brandAssetName {
                Image(assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: target.symbolName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

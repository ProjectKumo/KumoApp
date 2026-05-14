import AppKit
import SwiftUI
import KumoCoreKit

/// First-run setup sheet that walks the user through optional helpers:
/// installing the `kumo` CLI shim and registering the bundled Agent Skill
/// in supported coding agents. Designed so every step can be skipped — the
/// user always ends on `done` and the completion flag is persisted there.
///
/// Visual language follows the rest of the app: Liquid Glass surfaces via
/// `kumoGlassCard` / `kumoInteractiveGlass`, native macOS controls, and the
/// shared `AgentBrandIcon` so the Skills step renders the same brand PNGs as
/// the Agent Skills Configure page.
struct OnboardingView: View {
    @Environment(KumoAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var step: OnboardingStep = .welcome
    @State private var cliStatus = CLILinkStatus(
        state: .notInstalled,
        targetPath: CLILinkInstaller.defaultTargetPath,
        bundledCLIPath: nil,
        linkResolvedPath: nil,
        message: ""
    )
    @State private var cliBusy = false
    @State private var cliErrorMessage: String?
    @State private var skillStatuses: [AgentSkillsTargetStatus] = []
    @State private var skillSelection: Set<AgentSkillsTarget> = []
    @State private var skillBusy = false
    @State private var skillErrorMessage: String?
    @State private var installedSkillTargets: [AgentSkillsTarget] = []
    @State private var cliWasInstalled = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: step)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 20)

            stepContent
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.smooth(duration: 0.25), value: step)

            Divider()

            OnboardingFooter(
                step: step,
                primaryTitle: primaryButtonTitle,
                primaryDisabled: primaryButtonDisabled,
                primaryIsBusy: primaryIsBusy,
                onBack: handleBack,
                onSkip: handleSkip,
                onPrimary: handlePrimary
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 480)
        .background(.regularMaterial)
        .task { await loadInitialState() }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStepView()
        case .cli:
            CLIStepView(
                status: cliStatus,
                isBusy: cliBusy,
                errorMessage: cliErrorMessage
            )
        case .skills:
            SkillsStepView(
                statuses: skillStatuses,
                selection: $skillSelection,
                isBusy: skillBusy,
                errorMessage: skillErrorMessage
            )
        case .done:
            DoneStepView(
                cliInstalled: cliWasInstalled,
                installedSkillTargets: installedSkillTargets
            )
        }
    }

    // MARK: - Button state

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: "Continue"
        case .cli: cliStatus.isInstalled ? "Continue" : "Install"
        case .skills: skillSelection.isEmpty ? "Continue" : "Install Selected"
        case .done: "Finish"
        }
    }

    private var primaryButtonDisabled: Bool {
        switch step {
        case .welcome:
            return false
        case .cli:
            if cliStatus.isInstalled { return cliBusy }
            return cliBusy || cliStatus.state == .bundledCLIMissing
        case .skills:
            return skillBusy
        case .done:
            return false
        }
    }

    private var primaryIsBusy: Bool {
        (step == .cli && cliBusy) || (step == .skills && skillBusy)
    }

    // MARK: - Actions

    private func handleBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    private func handleSkip() {
        switch step {
        case .welcome:
            step = .cli
        case .cli:
            cliErrorMessage = nil
            step = .skills
        case .skills:
            skillErrorMessage = nil
            installedSkillTargets = []
            step = .done
        case .done:
            store.completeOnboarding()
            dismiss()
        }
    }

    private func handlePrimary() {
        switch step {
        case .welcome:
            step = .cli
        case .cli:
            if cliStatus.isInstalled {
                cliWasInstalled = true
                step = .skills
                return
            }
            Task { await installCLI() }
        case .skills:
            if skillSelection.isEmpty {
                step = .done
                return
            }
            Task { await installSelectedSkills() }
        case .done:
            store.completeOnboarding()
            dismiss()
        }
    }

    // MARK: - Async state loading

    private func loadInitialState() async {
        refreshCLIStatus()
        await refreshSkillStatuses()
    }

    private func refreshCLIStatus() {
        cliStatus = store.controller.cliLinkStatus()
        cliWasInstalled = cliStatus.isInstalled
    }

    private func refreshSkillStatuses() async {
        do {
            let installer = try AgentSkillsInstaller()
            let statuses = try installer.perTargetStatus(
                scope: .global,
                projectWorkingDirectory: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            )
            skillStatuses = statuses
        } catch {
            skillStatuses = []
            skillErrorMessage = displayMessage(for: error)
        }
    }

    private func installCLI() async {
        guard !cliBusy else { return }
        cliBusy = true
        cliErrorMessage = nil
        defer { cliBusy = false }

        do {
            cliStatus = try store.controller.installCLILink()
            cliWasInstalled = cliStatus.isInstalled
            if cliStatus.isInstalled {
                step = .skills
            }
        } catch {
            cliErrorMessage = displayMessage(for: error)
        }
    }

    private func installSelectedSkills() async {
        guard !skillBusy, !skillSelection.isEmpty else { return }
        skillBusy = true
        skillErrorMessage = nil
        defer { skillBusy = false }

        do {
            let installer = try AgentSkillsInstaller()
            _ = try installer.install(
                targets: skillSelection,
                scope: .global,
                projectWorkingDirectory: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
                dryRun: false,
                force: false
            )
            installedSkillTargets = AgentSkillsTarget.allCases.filter { skillSelection.contains($0) }
            await refreshSkillStatuses()
            step = .done
        } catch {
            skillErrorMessage = displayMessage(for: error)
        }
    }

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Step model

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case cli
    case skills
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to Kumo"
        case .cli: "Command Line Tool"
        case .skills: "Agent Skill"
        case .done: "All Set"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            "A native macOS Mihomo client. Take a moment to set up optional helpers."
        case .cli:
            "Install the kumo command so scripts and AI agents can drive Kumo from the terminal."
        case .skills:
            "Register the bundled Agent Skill in coding agents that follow the Skills protocol."
        case .done:
            "You can rerun setup any time from Settings."
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome: nil
        case .cli: .welcome
        case .skills: .cli
        case .done: .skills
        }
    }
}

// MARK: - Header & footer

private struct OnboardingHeader: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepIndicator(currentStep: step)

            HStack(alignment: .center, spacing: 14) {
                if step == .welcome, let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(step == .welcome ? .title.weight(.semibold) : .title2.weight(.semibold))
                    Text(step.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingStepIndicator: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.18))
                    .frame(width: step == currentStep ? 26 : 12, height: 4)
            }
        }
        .animation(.snappy, value: currentStep)
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}

private struct OnboardingFooter: View {
    let step: OnboardingStep
    let primaryTitle: String
    let primaryDisabled: Bool
    let primaryIsBusy: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if step.previous != nil {
                Button("Back", action: onBack)
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if step != .welcome, step != .done {
                Button("Skip", action: onSkip)
            }

            Button(action: onPrimary) {
                HStack(spacing: 6) {
                    if primaryIsBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryTitle)
                }
                .frame(minWidth: 88)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(primaryDisabled)
        }
    }
}

// MARK: - Step views

private struct WelcomeStepView: View {
    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let description: String
    }

    private let features: [Feature] = [
        Feature(
            symbol: "terminal",
            title: "Drive Kumo from the terminal",
            description: "Use the kumo CLI from scripts, CI, or coding agents."
        ),
        Feature(
            symbol: "sparkles",
            title: "Agent Skill ready to install",
            description: "Register the bundled Kumo skill in Cursor, Claude Code, Codex, and more."
        ),
        Feature(
            symbol: "gearshape.2",
            title: "Everything is optional",
            description: "You can skip any step now and revisit them from Settings later."
        )
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(features) { feature in
                FeatureRow(symbol: feature.symbol, title: feature.title, description: feature.description)
            }
        }
    }

    private struct FeatureRow: View {
        let symbol: String
        let title: String
        let description: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kumoGlassCard(cornerRadius: 14, tint: .accentColor.opacity(0.04))
        }
    }
}

private struct CLIStepView: View {
    let status: CLILinkStatus
    let isBusy: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard

            pathCard

            footnote

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusTint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 14, tint: statusTint.opacity(0.08))
    }

    @ViewBuilder
    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Target") {
                Text(status.targetPath)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let bundledCLIPath = status.bundledCLIPath {
                Divider().opacity(0.4)
                LabeledContent("Source") {
                    Text(bundledCLIPath)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var footnote: some View {
        Text(footnoteText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var footnoteText: String {
        if status.state == .bundledCLIMissing {
            return "Build the Kumo app bundle (make app) so the kumo binary is included before installing the CLI link."
        }
        return "macOS will ask for administrator authorization once because /usr/local/bin requires elevated privileges."
    }

    private var statusSymbol: String {
        switch status.state {
        case .installed: "checkmark.seal.fill"
        case .notInstalled: "terminal"
        case .differentSymlink, .occupiedByOther: "exclamationmark.triangle.fill"
        case .bundledCLIMissing: "questionmark.diamond.fill"
        }
    }

    private var statusTint: Color {
        switch status.state {
        case .installed: .green
        case .notInstalled: .accentColor
        case .differentSymlink, .occupiedByOther: .orange
        case .bundledCLIMissing: .secondary
        }
    }

    private var statusTitle: String {
        switch status.state {
        case .installed: "Installed"
        case .notInstalled: "Not installed yet"
        case .differentSymlink: "Different symlink"
        case .occupiedByOther: "Path occupied"
        case .bundledCLIMissing: "CLI binary missing"
        }
    }
}

private struct SkillsStepView: View {
    let statuses: [AgentSkillsTargetStatus]
    @Binding var selection: Set<AgentSkillsTarget>
    let isBusy: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(AgentSkillsTarget.allCases) { target in
                        SkillTargetRow(
                            target: target,
                            status: statuses.first { $0.target == target },
                            isSelected: binding(for: target)
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.never)

            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing selected agents...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func binding(for target: AgentSkillsTarget) -> Binding<Bool> {
        Binding {
            selection.contains(target)
        } set: { value in
            if value {
                selection.insert(target)
            } else {
                selection.remove(target)
            }
        }
    }
}

private struct SkillTargetRow: View {
    let target: AgentSkillsTarget
    let status: AgentSkillsTargetStatus?
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AgentBrandIcon(target: target, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(target.displayName)
                        .font(.body.weight(.medium))
                    statusChip
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kumoGlassCard(cornerRadius: 14, tint: isSelected ? .accentColor.opacity(0.06) : .clear)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { isSelected.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private var statusChip: some View {
        if let title = chipTitle {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(chipTint)
                .background(
                    Capsule().fill(chipTint.opacity(0.14))
                )
        }
    }

    private var chipTitle: String? {
        if status?.upToDate == true { return "Installed" }
        if status?.installed == true { return "Update Available" }
        return nil
    }

    private var chipTint: Color {
        if status?.upToDate == true { return .green }
        if status?.installed == true { return .orange }
        return .secondary
    }

    private var detailText: String {
        status?.destinationRoot ?? "Not registered yet"
    }
}

private struct DoneStepView: View {
    let cliInstalled: Bool
    let installedSkillTargets: [AgentSkillsTarget]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCheckmark
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

            SummaryRow(
                symbol: cliInstalled ? "checkmark.seal.fill" : "ellipsis.circle.fill",
                tint: cliInstalled ? .green : .secondary,
                title: "Command line tool",
                detail: cliInstalled
                    ? "Installed at \(CLILinkInstaller.defaultTargetPath)"
                    : "Not installed. You can add it later from Settings."
            )

            SummaryRow(
                symbol: installedSkillTargets.isEmpty ? "ellipsis.circle.fill" : "checkmark.seal.fill",
                tint: installedSkillTargets.isEmpty ? .secondary : .green,
                title: "Agent skill",
                detail: installedSkillTargets.isEmpty
                    ? "No agents registered. Use Agent Skills view to install later."
                    : "Registered with: \(installedSkillTargets.map { $0.displayName }.joined(separator: ", "))"
            )

            Spacer(minLength: 0)

            Text("Start Kumo's core from the toolbar to begin proxying traffic. Profiles, system proxy, and TUN are available from the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var heroCheckmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.green)
            .frame(width: 64, height: 64)
            .kumoGlassCard(cornerRadius: 32, tint: .green.opacity(0.10))
            .accessibilityHidden(true)
    }

    private struct SummaryRow: View {
        let symbol: String
        let tint: Color
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kumoGlassCard(cornerRadius: 14)
        }
    }
}

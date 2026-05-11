import Foundation

public enum AgentSkillsScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case global
    case project

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .global: "Global"
        case .project: "Project"
        }
    }
}

public enum AgentSkillsTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case claude
    case codex
    case gemini
    case agents

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        case .agents: "Generic .agents"
        }
    }

    public var symbolName: String {
        switch self {
        case .cursor: "cursorarrow"
        case .claude: "bubble.left.and.bubble.right"
        case .codex: "terminal"
        case .gemini: "sparkles"
        case .agents: "person.2"
        }
    }

    public var brandAssetName: String? {
        switch self {
        case .cursor: "agent-cursor"
        case .claude: "agent-claude"
        case .codex: "agent-codex"
        case .gemini: "agent-gemini"
        case .agents: nil
        }
    }

    public var supportsProjectScope: Bool {
        switch self {
        case .cursor, .claude, .agents: true
        case .codex, .gemini: false
        }
    }
}

public struct AgentSkillsManifest: Codable, Sendable, Equatable {
    public var bundleVersion: String
    public var skills: [AgentSkillsManifestEntry]
}

public struct AgentSkillsManifestEntry: Codable, Sendable, Equatable {
    public var id: String
    public var relativePath: String
}

public struct AgentSkillsInstallEntry: Codable, Sendable, Equatable {
    public var target: String
    public var scope: String
    public var destinationRoot: String
    public var installedSkillIds: [String]
    public var bundleVersion: String
    public var installedAt: Date
}

public struct AgentSkillsInstallState: Codable, Sendable, Equatable {
    public var bundleVersion: String
    public var scope: String
    public var destinationRoot: String
    public var destinationRoots: [String]
    public var installedSkillIds: [String]
    public var installedAt: Date
    public var entries: [AgentSkillsInstallEntry]
}

public struct AgentSkillsTargetStatus: Codable, Sendable, Equatable, Identifiable {
    public var target: AgentSkillsTarget
    public var scope: AgentSkillsScope
    public var destinationRoot: String
    public var supported: Bool
    public var installed: Bool
    public var installedBundleVersion: String?
    public var installedSkillIds: [String]
    public var manifestSkillIds: [String]
    public var upToDate: Bool

    public var id: String { "\(scope.rawValue):\(target.rawValue)" }
}

public struct AgentSkillsStatusPayload: Codable, Sendable, Equatable {
    public var bundleVersionInPackage: String
    public var manifestSkillIds: [String]
    public var scope: AgentSkillsScope
    public var targets: [AgentSkillsTargetStatus]
}

public struct AgentSkillsInstallReport: Codable, Sendable, Equatable {
    public var destinationRoot: String
    public var destinationRoots: [String]
    public var bundleVersion: String
    public var copiedSkillIds: [String]
    public var dryRun: Bool
}

public struct AgentSkillsInstaller: Sendable {
    private let bundleRoot: URL
    private let paths: KumoPaths
    private let homeDirectory: URL
    private let codexBaseDirectoryOverride: URL?

    public init(
        bundleRoot: URL? = nil,
        paths: KumoPaths = KumoPaths(),
        homeDirectory: URL? = nil,
        codexBaseDirectoryOverride: URL? = nil
    ) throws {
        self.paths = paths
        self.homeDirectory = homeDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.codexBaseDirectoryOverride = codexBaseDirectoryOverride
        self.bundleRoot = try bundleRoot ?? Self.defaultBundledSkillsRoot()
    }

    public static func defaultBundledSkillsRoot() throws -> URL {
        guard let resourceURL = Bundle.module.resourceURL else {
            throw KumoError.agentSkillsFailed("Missing KumoCoreKit resource bundle.")
        }
        let root = resourceURL.appendingPathComponent("KumoAgentSkills", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw KumoError.agentSkillsFailed("KumoAgentSkills folder not found in bundle.")
        }
        return root
    }

    public static func supportedTargets(for scope: AgentSkillsScope) -> [AgentSkillsTarget] {
        AgentSkillsTarget.allCases.filter { scope == .global || $0.supportsProjectScope }
    }

    public func destinationRoot(
        for target: AgentSkillsTarget,
        scope: AgentSkillsScope,
        projectWorkingDirectory: URL
    ) -> URL? {
        switch scope {
        case .global:
            return globalRoot(for: target)
        case .project:
            return projectRoot(for: target, projectWorkingDirectory: projectWorkingDirectory)
        }
    }

    public func globalRoot(for target: AgentSkillsTarget) -> URL {
        switch target {
        case .cursor:
            homeDirectory.appendingPathComponent(".cursor/skills", isDirectory: true)
        case .claude:
            homeDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
        case .codex:
            codexBaseDirectory().appendingPathComponent("skills", isDirectory: true)
        case .gemini:
            homeDirectory.appendingPathComponent(".gemini/skills", isDirectory: true)
        case .agents:
            homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
        }
    }

    public func projectRoot(for target: AgentSkillsTarget, projectWorkingDirectory: URL) -> URL? {
        guard target.supportsProjectScope else { return nil }
        switch target {
        case .cursor:
            return projectWorkingDirectory.appendingPathComponent(".cursor/skills", isDirectory: true)
        case .claude:
            return projectWorkingDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
        case .agents:
            return projectWorkingDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
        case .codex, .gemini:
            return nil
        }
    }

    public func loadManifest() throws -> AgentSkillsManifest {
        let url = bundleRoot.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AgentSkillsManifest.self, from: data)
    }

    public func validateBundledSkills() throws {
        let manifest = try loadManifest()
        try validateManifest(manifest)
        for entry in manifest.skills {
            let source = bundleRoot.appendingPathComponent(entry.relativePath, isDirectory: true)
            try validateSkill(at: source, expectedID: entry.id)
        }
    }

    public func readState() -> AgentSkillsInstallState? {
        let url = paths.agentSkillsStateFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentSkillsInstallState.self, from: data)
    }

    public func status(
        targets: Set<AgentSkillsTarget>? = nil,
        scope: AgentSkillsScope,
        projectWorkingDirectory: URL
    ) throws -> AgentSkillsStatusPayload {
        let manifest = try loadManifest()
        let selectedTargets = resolvedTargets(targets, scope: scope)
        return AgentSkillsStatusPayload(
            bundleVersionInPackage: manifest.bundleVersion,
            manifestSkillIds: manifest.skills.map { $0.id },
            scope: scope,
            targets: try perTargetStatus(
                targets: Set(selectedTargets),
                scope: scope,
                projectWorkingDirectory: projectWorkingDirectory
            )
        )
    }

    public func perTargetStatus(
        targets: Set<AgentSkillsTarget>? = nil,
        scope: AgentSkillsScope,
        projectWorkingDirectory: URL
    ) throws -> [AgentSkillsTargetStatus] {
        let manifest = try loadManifest()
        let manifestIDs = manifest.skills.map { $0.id }
        let entries = currentEntries()
        return resolvedTargets(targets, scope: scope).map { target in
            let destination = destinationRoot(
                for: target,
                scope: scope,
                projectWorkingDirectory: projectWorkingDirectory
            )
            let matchingEntry = entries.first { entry in
                entry.target == target.rawValue
                    && entry.scope == scope.rawValue
                    && destination?.path == entry.destinationRoot
            }
            let installedSkillIds = matchingEntry?.installedSkillIds ?? []
            let upToDate = matchingEntry?.bundleVersion == manifest.bundleVersion
                && Set(installedSkillIds) == Set(manifestIDs)

            return AgentSkillsTargetStatus(
                target: target,
                scope: scope,
                destinationRoot: destination?.path ?? "",
                supported: destination != nil,
                installed: matchingEntry != nil,
                installedBundleVersion: matchingEntry?.bundleVersion,
                installedSkillIds: installedSkillIds,
                manifestSkillIds: manifestIDs,
                upToDate: upToDate
            )
        }
    }

    public func install(
        targets: Set<AgentSkillsTarget>? = nil,
        scope: AgentSkillsScope,
        projectWorkingDirectory: URL,
        dryRun: Bool,
        force: Bool
    ) throws -> AgentSkillsInstallReport {
        let manifest = try loadManifest()
        try validateManifest(manifest)
        let selectedTargets = resolvedTargets(targets, scope: scope)
        guard !selectedTargets.isEmpty else {
            throw KumoError.agentSkillsFailed("Select at least one agent to install.")
        }

        let resolved = try selectedTargets.map { target in
            guard let root = destinationRoot(
                for: target,
                scope: scope,
                projectWorkingDirectory: projectWorkingDirectory
            ) else {
                throw KumoError.agentSkillsFailed("\(target.displayName) does not support \(scope.rawValue) scope.")
            }
            try validateDestinationRoot(root)
            return (target: target, root: root)
        }

        for entry in manifest.skills {
            let source = bundleRoot.appendingPathComponent(entry.relativePath, isDirectory: true)
            try validateSkill(at: source, expectedID: entry.id)
        }

        for destination in resolved {
            try prepareSkillDirectories(
                manifest: manifest,
                target: destination.target,
                scope: scope,
                destinationRoot: destination.root,
                dryRun: dryRun,
                force: force
            )
        }

        let destinationRoots = resolved.map { $0.root.path }
        let skillIDs = manifest.skills.map { $0.id }

        guard !dryRun else {
            return AgentSkillsInstallReport(
                destinationRoot: destinationRoots.first ?? "",
                destinationRoots: destinationRoots,
                bundleVersion: manifest.bundleVersion,
                copiedSkillIds: skillIDs,
                dryRun: true
            )
        }

        for destination in resolved {
            try FileManager.default.createDirectory(at: destination.root, withIntermediateDirectories: true)
            for entry in manifest.skills {
                let source = bundleRoot.appendingPathComponent(entry.relativePath, isDirectory: true)
                let target = destination.root.appendingPathComponent(entry.id, isDirectory: true)
                try copyDirectory(from: source, to: target)
            }
        }

        let now = Date()
        let newEntries = resolved.map { destination in
            AgentSkillsInstallEntry(
                target: destination.target.rawValue,
                scope: scope.rawValue,
                destinationRoot: destination.root.path,
                installedSkillIds: skillIDs,
                bundleVersion: manifest.bundleVersion,
                installedAt: now
            )
        }
        try mergeAndPersistEntries(upserts: newEntries, removals: [])

        return AgentSkillsInstallReport(
            destinationRoot: destinationRoots.first ?? "",
            destinationRoots: destinationRoots,
            bundleVersion: manifest.bundleVersion,
            copiedSkillIds: skillIDs,
            dryRun: false
        )
    }

    public func uninstall(
        targets: Set<AgentSkillsTarget>? = nil,
        scope: AgentSkillsScope? = nil,
        projectWorkingDirectory: URL,
        dryRun: Bool
    ) throws -> AgentSkillsInstallReport {
        let entries = currentEntries().filter { entry in
            let matchesTarget = targets?.contains { $0.rawValue == entry.target } ?? true
            let matchesScope = scope?.rawValue == entry.scope || scope == nil
            let matchesRoot = matchesDestinationRoot(entry, projectWorkingDirectory: projectWorkingDirectory)
            return matchesTarget && matchesScope && matchesRoot
        }

        guard !entries.isEmpty else {
            throw KumoError.agentSkillsFailed("No matching agent skills install.")
        }

        let destinationRoots = entries.map { $0.destinationRoot }
        let skillIDs = Array(Set(entries.flatMap { $0.installedSkillIds })).sorted()
        let bundleVersion = entries.first?.bundleVersion ?? ""

        guard !dryRun else {
            return AgentSkillsInstallReport(
                destinationRoot: destinationRoots.first ?? "",
                destinationRoots: destinationRoots,
                bundleVersion: bundleVersion,
                copiedSkillIds: skillIDs,
                dryRun: true
            )
        }

        for entry in entries {
            try removeInstalledSkills(at: entry)
        }
        try mergeAndPersistEntries(upserts: [], removals: entries)

        return AgentSkillsInstallReport(
            destinationRoot: destinationRoots.first ?? "",
            destinationRoots: destinationRoots,
            bundleVersion: bundleVersion,
            copiedSkillIds: skillIDs,
            dryRun: false
        )
    }

    private func codexBaseDirectory() -> URL {
        if let codexBaseDirectoryOverride {
            return codexBaseDirectoryOverride
        }
        let rawValue = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawValue.isEmpty {
            return URL(fileURLWithPath: rawValue, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    private func resolvedTargets(_ targets: Set<AgentSkillsTarget>?, scope: AgentSkillsScope) -> [AgentSkillsTarget] {
        let supported = Self.supportedTargets(for: scope)
        guard let targets else {
            return supported
        }
        return supported.filter { targets.contains($0) }
    }

    private func currentEntries() -> [AgentSkillsInstallEntry] {
        readState()?.entries ?? []
    }

    private func matchesDestinationRoot(
        _ entry: AgentSkillsInstallEntry,
        projectWorkingDirectory: URL
    ) -> Bool {
        guard let target = AgentSkillsTarget(rawValue: entry.target),
              let scope = AgentSkillsScope(rawValue: entry.scope),
              let root = destinationRoot(for: target, scope: scope, projectWorkingDirectory: projectWorkingDirectory) else {
            return false
        }
        return root.path == entry.destinationRoot
    }

    private func validateManifest(_ manifest: AgentSkillsManifest) throws {
        guard !manifest.bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KumoError.agentSkillsFailed("Manifest bundleVersion is required.")
        }
        guard !manifest.skills.isEmpty else {
            throw KumoError.agentSkillsFailed("Manifest must include at least one skill.")
        }
        for entry in manifest.skills {
            guard isValidSkillName(entry.id) else {
                throw KumoError.agentSkillsFailed("Invalid skill id: \(entry.id).")
            }
            guard isSafeRelativePath(entry.relativePath) else {
                throw KumoError.agentSkillsFailed("Invalid skill path for \(entry.id): \(entry.relativePath).")
            }
        }
    }

    private func validateSkill(at url: URL, expectedID: String) throws {
        let skillFile = url.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
            throw KumoError.agentSkillsFailed("Missing SKILL.md for \(expectedID).")
        }
        let contents = try String(contentsOf: skillFile, encoding: .utf8)
        let lineCount = contents.split(separator: "\n", omittingEmptySubsequences: false).count
        guard lineCount <= 500 else {
            throw KumoError.agentSkillsFailed("\(expectedID) SKILL.md exceeds 500 lines.")
        }
        let frontmatter = try parseFrontmatter(contents)
        guard frontmatter.name == expectedID else {
            throw KumoError.agentSkillsFailed("Skill name \(frontmatter.name) does not match manifest id \(expectedID).")
        }
        guard isValidSkillName(frontmatter.name) else {
            throw KumoError.agentSkillsFailed("Invalid skill name: \(frontmatter.name).")
        }
        guard !frontmatter.description.isEmpty else {
            throw KumoError.agentSkillsFailed("\(expectedID) description is required.")
        }
        guard frontmatter.description.count <= 1_024 else {
            throw KumoError.agentSkillsFailed("\(expectedID) description exceeds 1024 characters.")
        }
    }

    private func parseFrontmatter(_ contents: String) throws -> SkillFrontmatter {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else {
            throw KumoError.agentSkillsFailed("SKILL.md must start with YAML frontmatter.")
        }

        var name: String?
        var description: String?
        for line in lines.dropFirst() {
            if line == "---" {
                break
            }
            if line.hasPrefix("name:") {
                name = String(line.dropFirst("name:".count)).trimmedSkillValue
            } else if line.hasPrefix("description:") {
                description = String(line.dropFirst("description:".count)).trimmedSkillValue
            }
        }

        guard let name, let description else {
            throw KumoError.agentSkillsFailed("SKILL.md frontmatter requires name and description.")
        }
        return SkillFrontmatter(name: name, description: description)
    }

    private func validateDestinationRoot(_ url: URL) throws {
        if url.standardizedFileURL.path.contains("/.cursor/skills-cursor") {
            throw KumoError.agentSkillsFailed("Refusing to install into Cursor's internal skills directory.")
        }
    }

    private func prepareSkillDirectories(
        manifest: AgentSkillsManifest,
        target: AgentSkillsTarget,
        scope: AgentSkillsScope,
        destinationRoot: URL,
        dryRun: Bool,
        force: Bool
    ) throws {
        let entries = currentEntries()
        for entry in manifest.skills {
            let destination = destinationRoot.appendingPathComponent(entry.id, isDirectory: true)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }

            let installedByKumo = entries.contains { stored in
                let sameTarget = stored.target == target.rawValue
                let sameScope = stored.scope == scope.rawValue
                let sameRoot = stored.destinationRoot == destinationRoot.path
                return sameTarget && sameScope && sameRoot && stored.installedSkillIds.contains(entry.id)
            }
            guard installedByKumo || force else {
                throw KumoError.agentSkillsFailed(
                    "Skill directory already exists at \(destination.path). Use --force only if replacing it is intended."
                )
            }
            if !dryRun {
                try FileManager.default.removeItem(at: destination)
            }
        }
    }

    private func removeInstalledSkills(at entry: AgentSkillsInstallEntry) throws {
        let root = URL(fileURLWithPath: entry.destinationRoot, isDirectory: true)
        for id in entry.installedSkillIds {
            let directory = root.appendingPathComponent(id, isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func mergeAndPersistEntries(
        upserts: [AgentSkillsInstallEntry],
        removals: [AgentSkillsInstallEntry]
    ) throws {
        var entries = currentEntries()
        for removal in removals {
            entries.removeAll { entry in
                entry.target == removal.target
                    && entry.scope == removal.scope
                    && entry.destinationRoot == removal.destinationRoot
            }
        }
        for upsert in upserts {
            entries.removeAll { entry in
                entry.target == upsert.target
                    && entry.scope == upsert.scope
                    && entry.destinationRoot == upsert.destinationRoot
            }
            entries.append(upsert)
        }

        if entries.isEmpty {
            try? FileManager.default.removeItem(at: paths.agentSkillsStateFile)
            return
        }

        try FileManager.default.createDirectory(
            at: paths.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let primary = entries[0]
        let state = AgentSkillsInstallState(
            bundleVersion: primary.bundleVersion,
            scope: primary.scope,
            destinationRoot: primary.destinationRoot,
            destinationRoots: entries.map { $0.destinationRoot },
            installedSkillIds: primary.installedSkillIds,
            installedAt: Date(),
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: paths.agentSkillsStateFile, options: [.atomic])
    }

    private func copyDirectory(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for sourceURL in contents {
            let destinationURL = destination.appendingPathComponent(sourceURL.lastPathComponent)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                try copyDirectory(from: sourceURL, to: destinationURL)
            } else {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.split(separator: "/").contains("..")
    }

    private func isValidSkillName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9-]{1,64}$"#, options: .regularExpression) != nil
    }
}

private struct SkillFrontmatter {
    var name: String
    var description: String
}

private extension String {
    var trimmedSkillValue: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
import ArgumentParser
import KumoCoreKit

struct SkillSelection: ParsableArguments {
    @Option(name: .long, help: "Agent target: cursor, claude, codex, gemini, agents, or all.")
    var agent: AgentTargetSelection = .all
    @Option(name: .long, help: "Install scope: global or project.")
    var scope: AgentSkillsScope = .global

    func targets() throws -> Set<AgentSkillsTarget>? {
        switch agent {
        case .all:
            return nil
        case .target(let target):
            guard scope == .global || target.supportsProjectScope else {
                throw ValidationError("\(target.displayName) does not support project scope.")
            }
            return [target]
        }
    }
}

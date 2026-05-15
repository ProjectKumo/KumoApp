import Foundation

struct OutputRenderer {
    let options: RuntimeOptions

    var usesColor: Bool {
        guard !options.wantsJSON else { return false }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        if ProcessInfo.processInfo.environment["CLICOLOR"] == "0" { return false }
        switch options.color {
        case .always:
            return true
        case .never:
            return false
        case .auto:
            return isatty(STDOUT_FILENO) == 1
        }
    }

    func stdout(_ value: String) {
        print(value)
    }

    func stderr(_ value: String) {
        fputs(value + "\n", Foundation.stderr)
    }

    func error(_ value: String) -> String {
        style(value, code: "31")
    }

    func dim(_ value: String) -> String {
        style(value, code: "2")
    }

    private func style(_ value: String, code: String) -> String {
        guard usesColor else { return value }
        return "\u{001B}[\(code)m\(value)\u{001B}[0m"
    }
}

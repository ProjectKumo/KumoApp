import ArgumentParser

struct CLIOptions: ParsableArguments {
    @Flag(name: .long, help: "Write machine-readable JSON.")
    var json = false
    @Option(name: .long, help: "Color output: always, auto, or never.")
    var color: ColorMode = .auto
    @Option(name: .long, help: "Log level: silent, error, warn, notice, http, info, verbose, or silly.")
    var loglevel: LogLevel = .notice
    @Flag(name: .long, help: "Suppress successful text output.")
    var silent = false
    @Flag(name: .long, help: "Show verbose diagnostics.")
    var verbose = false
    @Flag(name: .customShort("d"), help: "Show info diagnostics.")
    var debug = false
    @Option(name: .long, help: "Directory for CLI debug logs.")
    var logsDir: String?
    @Option(name: .long, help: "Maximum CLI debug log files to retain. Use 0 to disable file logs.")
    var logsMax: Int = 10
    @Flag(name: .long, help: "Write timing diagnostics.")
    var timing = false
    @Option(name: .long, help: "Progress output: true, false, or auto.")
    var progress: ProgressMode = .auto

    func install() throws {
        let runtime = CLIRuntime(options: RuntimeOptions(options: self))
        runtime.log(.info, "using service backend: auto")
    }
}

struct RuntimeOptions {
    var wantsJSON: Bool
    var color: ColorMode
    var logLevel: LogLevel
    var isSilent: Bool
    var logsDir: String?
    var logsMax: Int
    var timing: Bool
    var progress: ProgressMode

    init(arguments: [String]) {
        self.wantsJSON = arguments.contains("--json")
        self.color = Self.value(after: "--color", in: arguments).flatMap(ColorMode.init(argument:)) ?? .auto
        let rawLevel = Self.value(after: "--loglevel", in: arguments).flatMap(LogLevel.init(argument:))
        if arguments.contains("--silent") {
            self.logLevel = .silent
            self.isSilent = true
        } else if arguments.contains("--verbose") {
            self.logLevel = .verbose
            self.isSilent = false
        } else if arguments.contains("-d") {
            self.logLevel = .info
            self.isSilent = false
        } else {
            self.logLevel = rawLevel ?? .notice
            self.isSilent = rawLevel == .silent
        }
        self.logsDir = Self.value(after: "--logs-dir", in: arguments)
        self.logsMax = Self.value(after: "--logs-max", in: arguments).flatMap(Int.init) ?? 10
        self.timing = arguments.contains("--timing")
        self.progress = Self.value(after: "--progress", in: arguments).flatMap(ProgressMode.init(argument:)) ?? .auto
    }

    init(options: CLIOptions) {
        self.wantsJSON = options.json
        self.color = options.color
        if options.silent {
            self.logLevel = .silent
        } else if options.verbose {
            self.logLevel = .verbose
        } else if options.debug {
            self.logLevel = .info
        } else {
            self.logLevel = options.loglevel
        }
        self.isSilent = options.silent || logLevel == .silent
        self.logsDir = options.logsDir
        self.logsMax = options.logsMax
        self.timing = options.timing
        self.progress = options.progress
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

import OSLog

enum AppLog {
    static let subsystem = "aloes"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let search = Logger(subsystem: subsystem, category: "search")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let commands = Logger(subsystem: subsystem, category: "commands")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let sentry = Logger(subsystem: subsystem, category: "sentry")
}

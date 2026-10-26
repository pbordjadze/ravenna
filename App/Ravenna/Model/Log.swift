import os

/// The app's loggers, a category per area.
nonisolated enum Log {
    private static let subsystem = "com.pbordjadze.paintbynumber"

    static let library = Logger(subsystem: subsystem, category: "library")
    static let create = Logger(subsystem: subsystem, category: "create")
    static let canvas = Logger(subsystem: subsystem, category: "canvas")
    static let tips = Logger(subsystem: subsystem, category: "tips")
    static let feedback = Logger(subsystem: subsystem, category: "feedback")
    static let store = Logger(subsystem: subsystem, category: "store")
    #if DEBUG
    static let demo = Logger(subsystem: subsystem, category: "demo")
    #endif
}

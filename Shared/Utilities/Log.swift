import os

enum Log {
    private static let subsystem = "com.lincode.PersonalIsland"

    static let island = Logger(subsystem: subsystem, category: "island")
    static let screenshots = Logger(subsystem: subsystem, category: "screenshots")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let filesystem = Logger(subsystem: subsystem, category: "filesystem")
    static let nowPlaying = Logger(subsystem: subsystem, category: "nowPlaying")
    static let agentBridge = Logger(subsystem: subsystem, category: "agentBridge")
    static let agentStore = Logger(subsystem: subsystem, category: "agentStore")
    static let agentNotifications = Logger(subsystem: subsystem, category: "agentNotifications")
    static let agentIcons = Logger(subsystem: subsystem, category: "agentIcons")
    static let agentHooks = Logger(subsystem: subsystem, category: "agentHooks")
    static let attention = Logger(subsystem: subsystem, category: "attention")
}

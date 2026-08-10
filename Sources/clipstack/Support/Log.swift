import os

/// Логи смотреть в Console.app с фильтром по subsystem — Instruments и UI-дебага без Xcode нет,
/// os.Logger это основной инструмент диагностики в проекте.
enum Log {
    private static let subsystem = AppInfo.bundleID

    static let app = Logger(subsystem: subsystem, category: "app")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let paste = Logger(subsystem: subsystem, category: "paste")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

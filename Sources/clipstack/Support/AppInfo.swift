import Foundation

enum AppInfo {
    /// Захардкожен намеренно: используется в Log до того, как что-либо читает Info.plist,
    /// и при запуске бинаря напрямую из SPM (когда бандла ещё нет) Bundle.main пуст.
    /// Менять только вместе с CFBundleIdentifier в Resources/Info.plist — иначе разъедется
    /// designated requirement, и macOS сбросит выданное разрешение Универсального доступа.
    static let bundleID = "com.roriver.clipstack"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

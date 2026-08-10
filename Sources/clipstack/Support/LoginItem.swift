import Foundation
import ServiceManagement

/// Автозапуск при входе в систему.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Возвращает false, если система отказала. Частая причина — приложение запущено не из
    /// того места, где зарегистрировано (например, из папки сборки, а не из /Applications).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("автозапуск: \(enabled ? "включён" : "выключен", privacy: .public)")
            return true
        } catch {
            Log.app.error("автозапуск не переключился: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "включён"
        case .notRegistered: "выключен"
        case .notFound: "приложение не найдено системой"
        case .requiresApproval: "нужно подтвердить в Системных настройках → Основные → Объекты входа"
        @unknown default: "неизвестно"
        }
    }
}

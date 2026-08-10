import AppKit
import ApplicationServices

/// Проверка и запрос доступа к Универсальному доступу — без него нельзя синтезировать ⌘V.
enum AccessibilityGuard {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный диалог с предложением выдать доступ.
    /// Диалог появляется ОДИН раз на связку (приложение + designated requirement): повторный
    /// вызов после отказа молча вернёт false. Поэтому если пользователь отказался,
    /// дальше ведём его руками — через openSettings().
    @discardableResult
    static func requestAccess() -> Bool {
        // Строковый литерал вместо kAXTrustedCheckOptionPrompt: константа объявлена в C как
        // изменяемая глобальная, и Swift 6 не пускает её в конкурентный код. Значение
        // зафиксировано в ABI фреймворка и не меняется.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Объясняет, зачем доступ, и открывает системные настройки.
    @MainActor
    static func presentOnboarding() {
        let alert = NSAlert()
        alert.messageText = "clipstack нужен Универсальный доступ"
        alert.informativeText = """
            Без него приложение не сможет вставлять выбранное в активное окно — \
            элемент будет только попадать в буфер, а вставлять придётся вручную через ⌘V.

            Включи clipstack в списке:
            Системные настройки → Конфиденциальность и безопасность → Универсальный доступ
            """
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        // Мы .accessory-приложение: без явной активации диалог уедет за чужие окна.
        NSApp.activate()

        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }
}

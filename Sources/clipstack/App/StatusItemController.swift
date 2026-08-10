import AppKit

/// Иконка в меню-баре и её меню.
@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem

    var onShowHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    var showHotkey: KeyCombo = .defaultShow {
        didSet { rebuildMenu() }
    }

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        item.menu = buildMenu()
    }

    private func configureButton() {
        // macOS запоминает видимость статус-айтема между запусками и может вернуть его
        // скрытым. Ставим явно, иначе иконки просто не будет, и причина ниоткуда не видна.
        item.isVisible = true

        guard let button = item.button else {
            Log.app.error("у статус-айтема нет button — иконка не появится")
            return
        }

        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "clipstack")
        // isTemplate обязателен: иначе иконка не перекрасится под светлую/тёмную тему бара.
        image?.isTemplate = true
        button.image = image

        if image == nil {
            // Пустая кнопка схлопывается в ноль ширины и выглядит как «приложение не
            // запустилось». Текст хуже иконки, но заметно лучше пустоты.
            button.title = "CS"
        }

        // Запоминает, куда пользователь перетащил иконку (⌘+перетаскивание). Без этого на
        // маках с вырезом иконка каждый раз уезжает обратно под чёлку: система раскладывает
        // айтемы справа налево, и когда справа от выреза места нет, следующий попадает
        // ровно под него и становится невидимым.
        item.autosaveName = "clipstack.statusItem"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let history = NSMenuItem(
            title: "История  \(showHotkey.displayString)",
            action: #selector(showHistory),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let version = NSMenuItem(title: "Версия \(AppInfo.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let quit = NSMenuItem(
            title: "Выйти",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    private func rebuildMenu() {
        item.menu = buildMenu()
    }

    @objc private func showHistory() {
        onShowHistory?()
    }

    @objc private func openSettings() {
        // Следующим тактом, а не сразу: пока меню закрывается, AppKit крутит свой цикл
        // трекинга, и смена activation policy внутри него не применяется — окно настроек
        // открывается позади чужих окон.
        DispatchQueue.main.async { [weak self] in
            self?.onOpenSettings?()
        }
    }
}

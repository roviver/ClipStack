import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var history: HistoryService?
    private var panel: HistoryPanelController?
    private let hotkeys = HotkeyManager()
    private let paste = PasteService()
    private let preferences = Preferences()
    private let settingsWindow = SettingsWindowController()
    private var showHotkeyID: UInt32?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("clipstack \(AppInfo.version, privacy: .public) запущен")

        do {
            let history = try buildHistoryService()
            self.history = history
            applyPreferences(to: history)
            history.start()
            buildInterface(repository: history.repository)
            observePreferences()
        } catch {
            // Без хранилища приложение бессмысленно: молча работать «почти» хуже, чем
            // честно сказать, что сломалось.
            Log.app.critical("не удалось поднять хранилище: \(String(describing: error), privacy: .public)")
            presentFatal(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregisterAll()
        history?.stop()
        Log.app.info("clipstack завершается")
    }

    // MARK: - Сборка

    private func buildHistoryService() throws -> HistoryService {
        try Paths.ensureDirectories()
        let database = try Database(path: Paths.databaseFile)
        let repository = ClipRepository(database: database)
        Log.storage.info("история открыта, записей: \((try? repository.count()) ?? -1)")
        return HistoryService(repository: repository, monitor: PasteboardMonitor())
    }

    private func applyPreferences(to history: HistoryService) {
        history.historyLimit = preferences.historyLimit
        history.pollInterval = preferences.pollInterval
        history.ignoredBundleIDs = Set(preferences.ignoredBundleIDs)
        history.soundEnabled = preferences.soundEnabled
        history.soundName = preferences.soundName
    }

    private func buildInterface(repository: ClipRepository) {
        // Иначе монитор увидит нашу же запись в буфер и перетасует историю.
        paste.onPasteboardWritten = { [weak self] in
            self?.history?.acknowledgeOwnWrite()
        }

        let panel = HistoryPanelController(model: HistoryPanelModel(repository: repository))
        panel.onWillShow = { [weak self] in
            self?.paste.tracker.capture()
        }
        panel.onActivate = { [weak self] item in
            self?.paste.paste(item)
        }
        self.panel = panel

        let statusItem = StatusItemController()
        statusItem.showHotkey = preferences.showHotkey
        statusItem.onShowHistory = { [weak panel] in panel?.show() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        self.statusItem = statusItem

        registerShowHotkey(preferences.showHotkey)
    }

    private func observePreferences() {
        preferences.$ignoredBundleIDs
            .sink { [weak self] ids in self?.history?.ignoredBundleIDs = Set(ids) }
            .store(in: &cancellables)

        preferences.$historyLimit
            .sink { [weak self] limit in
                self?.history?.historyLimit = limit
                self?.history?.applyLimitNow()
            }
            .store(in: &cancellables)

        preferences.$soundEnabled
            .sink { [weak self] enabled in self?.history?.soundEnabled = enabled }
            .store(in: &cancellables)

        preferences.$soundName
            .sink { [weak self] name in self?.history?.soundName = name }
            .store(in: &cancellables)
    }

    // MARK: - Хоткей

    private func registerShowHotkey(_ combo: KeyCombo) {
        if let showHotkeyID {
            hotkeys.unregister(showHotkeyID)
        }
        do {
            showHotkeyID = try hotkeys.register(combo) { [weak self] in
                self?.panel?.toggle()
            }
            statusItem?.showHotkey = combo
        } catch {
            Log.hotkey.error("\(String(describing: error), privacy: .public)")
            // Не фатально: панель остаётся доступной через меню в баре.
            let alert = NSAlert()
            alert.messageText = "Не удалось занять горячую клавишу"
            alert.informativeText = """
                \(combo.displayString) уже занята другим приложением.
                Выбери другую комбинацию в настройках — история пока доступна через меню-бар.
                """
            NSApp.activate()
            alert.runModal()
        }
    }

    // MARK: - Настройки

    private func openSettings() {
        let view = SettingsView(
            preferences: preferences,
            onHotkeyChanged: { [weak self] combo in self?.registerShowHotkey(combo) },
            onClearHistory: { [weak self] keepPinned in self?.clearHistory(keepPinned: keepPinned) },
            onCountRequested: { [weak self] in
                guard let repository = self?.history?.repository else { return 0 }
                return (try? repository.count()) ?? 0
            }
        )
        settingsWindow.show(content: view)
    }

    private func clearHistory(keepPinned: Bool) {
        do {
            try history?.repository.clear(keepPinned: keepPinned)
            Log.storage.info("история очищена, закреплённые \(keepPinned ? "сохранены" : "тоже удалены", privacy: .public)")
        } catch {
            Log.storage.error("не удалось очистить историю: \(String(describing: error), privacy: .public)")
        }
    }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "clipstack не смог открыть хранилище"
        alert.informativeText = """
            \(String(describing: error))

            База лежит здесь:
            \(Paths.databaseFile.path)
            """
        alert.addButton(withTitle: "Выйти")
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}

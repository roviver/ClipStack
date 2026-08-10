import AppKit

/// Следит за системным буфером обмена.
///
/// NSPasteboard не умеет уведомлять об изменениях — ни нотификаций, ни колбэков в API нет.
/// Единственный рабочий способ, которым пользуются все менеджеры буфера, — опрашивать
/// changeCount по таймеру. Счётчик это просто целое в памяти демона pboard, так что опрос
/// стоит доли микросекунды и на батарее не заметен.
@MainActor
final class PasteboardMonitor {
    private let pasteboard: NSPasteboard
    private let reader: PasteboardReader
    private var timer: Timer?
    private var lastChangeCount: Int

    var filter: PrivacyFilter
    var onCapture: ((ClipDraft) -> Void)?

    init(
        pasteboard: NSPasteboard = .general,
        reader: PasteboardReader = PasteboardReader(),
        filter: PrivacyFilter = PrivacyFilter()
    ) {
        self.pasteboard = pasteboard
        self.reader = reader
        self.filter = filter
        // Стартуем с текущего значения: то, что лежало в буфере до запуска, не наше дело.
        self.lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.3) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Таймер добавлен в главный run loop, поэтому блок гарантированно на главном потоке.
            MainActor.assumeIsolated { self?.poll() }
        }
        // .common, иначе опрос замирает, пока открыто меню или пользователь тащит скроллбар.
        timer.tolerance = interval / 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.clipboard.info("мониторинг буфера запущен, интервал \(interval, format: .fixed(precision: 2)) с")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Признать текущее состояние буфера уже учтённым.
    /// Нужно после того, как мы сами положили что-то в буфер при вставке: иначе монитор
    /// поймает собственную запись и поднимет элемент наверх, ломая порядок истории.
    func acknowledgeOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        let source = currentSource()
        guard filter.allows(pasteboard, source: source) else { return }
        guard var draft = reader.read(pasteboard) else { return }

        draft.source = source
        onCapture?(draft)
    }

    /// Кто положил данные в буфер, определяем по активному приложению.
    /// NSPasteboard автора записи не сообщает вообще, так что это эвристика — но ровно та,
    /// на которой держатся все менеджеры буфера. Врёт она в редком случае: приложение
    /// пишет в буфер из фона, не будучи активным.
    private func currentSource() -> ClipSource? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        return ClipSource(bundleID: bundleID, appName: app.localizedName ?? bundleID)
    }
}

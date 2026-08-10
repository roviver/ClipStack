import AppKit

/// Кладёт элемент в буфер и вставляет его в то приложение, которое было активным.
@MainActor
final class PasteService {
    private let writer = PasteboardWriter()
    let tracker = FrontmostAppTracker()

    /// Вызывается сразу после записи в буфер, чтобы монитор не принял её за копию пользователя.
    var onPasteboardWritten: (() -> Void)?

    /// Показывать онбординг доступа не чаще одного раза за запуск — иначе диалог вылезает
    /// на каждую вставку и превращается в травлю.
    private var onboardingShown = false

    func paste(_ item: ClipItem) {
        guard writer.write(item) else {
            Log.paste.error("не удалось записать элемент #\(item.id) в буфер")
            return
        }
        onPasteboardWritten?()

        guard AccessibilityGuard.isTrusted else {
            // Не тупик: элемент уже в буфере, пользователь вставит руками.
            Log.paste.info("нет Универсального доступа — элемент только в буфере")
            if !onboardingShown {
                onboardingShown = true
                // Через Task, а не напрямую: paste() вызывается из обработчика нажатия клавиши,
                // внутри которого AppKit уже крутит свой цикл событий. Запущенный оттуда
                // runModal возвращается мгновенно, окно так и не показав.
                Task { @MainActor in AccessibilityGuard.presentOnboarding() }
            }
            return
        }

        Task { await performPaste(item) }
    }

    private func performPaste(_ item: ClipItem) async {
        guard await tracker.reactivate() else {
            Log.paste.info("некуда вставлять — элемент остался в буфере")
            return
        }

        await KeystrokeSynthesizer.waitForModifiersRelease()
        let posted = KeystrokeSynthesizer.pressCommandV()
        Log.paste.info("вставка элемента #\(item.id): \(posted ? "отправлена" : "не удалась", privacy: .public)")
    }
}

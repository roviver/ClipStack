import AppKit

/// Плавающая панель истории.
///
/// .nonactivatingPanel — ключевой флаг: панель принимает клавиатуру, НЕ делая clipstack
/// активным приложением. Без него открытие панели переключало бы фронт на нас, и к моменту
/// вставки система уже забыла бы, куда вставлять.
final class PanelWindow: NSPanel {
    /// NSPanel по умолчанию не становится key, а нам нужен ввод в поле поиска.
    override var canBecomeKey: Bool { true }
    /// Main-окном не становимся сознательно: это признак «приложение переднего плана».
    override var canBecomeMain: Bool { false }

    var onCancel: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        // hidesOnDeactivate = false, иначе панель исчезает раньше, чем мы успеваем прочитать
        // выбранный элемент при переключении фокуса.
        hidesOnDeactivate = false
        // .transient — чтобы панель не попадала в Mission Control и переключатель окон.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        backgroundColor = .clear
        hasShadow = true

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10
        contentView.layer?.masksToBounds = true
        self.contentView = contentView
    }

    /// Esc в AppKit приходит сюда, а не в keyDown.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Показывает панель по центру того экрана, где сейчас курсор — на многомониторной
    /// раскладке иначе она вылезает не там, где смотрит пользователь.
    func showCentered() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = frame.size
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
            setFrameOrigin(origin)
        }

        // Панель заявлена .nonactivatingPanel, но одного этого мало: если приложение не
        // активно, система не отдаёт панели статус key-окна, и ввод с клавиатуры уходит
        // мимо — в то приложение, что было впереди. Активируемся явно.
        //
        // Фокус при этом не теряется: цель вставки уже запомнена в onWillShow, а
        // FrontmostAppTracker вернёт её перед самой вставкой.
        orderFrontRegardless()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

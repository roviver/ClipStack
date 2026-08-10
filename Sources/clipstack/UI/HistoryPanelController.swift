import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Показывает и прячет панель истории, обрабатывает клавиатуру внутри неё.
@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let model: HistoryPanelModel
    private var window: PanelWindow?
    private var keyMonitor: Any?

    /// Что делать с выбранным элементом.
    var onActivate: ((ClipItem) -> Void)?

    /// Вызывается ДО появления окна — момент, когда ещё видно, какое приложение активно.
    var onWillShow: (() -> Void)?

    init(model: HistoryPanelModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        // Строго до makeKeyAndOrderFront: после него фронтмостом может стать уже не тот,
        // в кого нужно вставлять.
        onWillShow?()

        model.query = ""
        model.activeKind = nil
        model.showPinnedOnly = false
        model.reload()

        let window = window ?? makeWindow()
        self.window = window
        window.showCentered()
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        window?.orderOut(nil)
    }

    // MARK: - Окно

    private func makeWindow() -> PanelWindow {
        let hosting = NSHostingView(
            rootView: ClipListView(model: model) { [weak self] item in
                self?.activate(item)
            }
        )
        let window = PanelWindow(contentView: hosting)
        window.delegate = self
        window.onCancel = { [weak self] in self?.hide() }
        return window
    }

    private func activate(_ item: ClipItem) {
        hide()
        onActivate?(item)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Клик мимо панели = отказ от выбора. Ведёт себя как Spotlight.
        hide()
    }

    // MARK: - Клавиатура

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Сам NSEvent не Sendable, поэтому внутрь изоляции передаём только выжимку из
            // него — значения примитивных типов. Монитор и так вызывается на главном потоке.
            let keyCode = Int(event.keyCode)
            let modifiers = event.modifierFlags
            let characters = event.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated {
                self.handle(keyCode: keyCode, modifiers: modifiers, characters: characters)
            }
            // Возврат nil поглощает событие, иначе оно уйдёт дальше в поле поиска.
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handle(keyCode: Int, modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard window?.isKeyWindow == true else { return false }

        // ⌘1…⌘9 — мгновенный выбор строки без хождения стрелками.
        if modifiers.contains(.command),
           let characters,
           let digit = Int(characters), (1...9).contains(digit) {
            model.select(index: digit - 1)
            if let item = model.selectedItem { activate(item) }
            return true
        }

        // ⌘P — закрепить, ⌘⌫ — удалить. Голый Backspace не годится: он должен править
        // строку поиска, а не сносить записи из истории.
        if modifiers.contains(.command) {
            switch keyCode {
            case kVK_ANSI_P:
                model.togglePinSelected()
                return true
            case kVK_Delete:
                model.deleteSelected()
                return true
            default:
                break
            }
        }

        switch keyCode {
        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return true
        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return true
        case kVK_PageDown:
            model.moveSelection(by: 10)
            return true
        case kVK_PageUp:
            model.moveSelection(by: -10)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem { activate(item) }
            return true
        case kVK_Escape:
            hide()
            return true
        default:
            return false
        }
    }
}

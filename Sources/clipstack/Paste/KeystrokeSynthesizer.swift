import AppKit
import Carbon.HIToolbox

/// Синтез нажатия ⌘V в активное окно.
enum KeystrokeSynthesizer {
    /// Ждёт, пока пользователь отпустит все модификаторы.
    ///
    /// Это не перестраховка: панель вызывается по ⇧⌘V, и если послать ⌘V, пока Shift ещё
    /// зажат, система увидит ⇧⌘V — то есть наш же хоткей, и панель откроется заново вместо
    /// вставки. Ловушка воспроизводится всегда, когда пользователь бьёт по Enter быстро.
    static func waitForModifiersRelease(timeout: TimeInterval = 0.6) async {
        let watched: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let state = CGEventSource.flagsState(.combinedSessionState)
            if state.intersection(watched).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(15))
        }
        Log.paste.debug("модификаторы так и не отпустили за \(timeout, format: .fixed(precision: 2)) с")
    }

    @discardableResult
    static func pressCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Log.paste.error("не удалось создать CGEventSource")
            return false
        }

        // Гасим влияние реально зажатых клавиш на наши синтетические события.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let key = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            Log.paste.error("не удалось создать события клавиатуры")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // .cgAnnotatedSessionEventTap доставляет событие активному приложению так же,
        // как это делает физическая клавиатура.
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}

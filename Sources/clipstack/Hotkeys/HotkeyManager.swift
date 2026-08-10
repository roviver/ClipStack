import AppKit
import Carbon.HIToolbox

enum HotkeyError: Error, CustomStringConvertible {
    case registrationFailed(OSStatus)

    var description: String {
        switch self {
        case .registrationFailed(let code):
            "не удалось зарегистрировать хоткей (код \(code)) — вероятно, комбинация уже занята"
        }
    }
}

/// Глобальные горячие клавиши через Carbon.
///
/// Почему Carbon, а не NSEvent: глобальные мониторы NSEvent только НАБЛЮДАЮТ за нажатиями и
/// не могут перехватить комбинацию — она уйдёт и в активное приложение тоже. CGEvent tap умеет
/// перехватывать, но требует разрешения Универсального доступа ещё до первого запуска.
/// RegisterEventHotKey не требует никаких разрешений и остаётся штатным способом в macOS 26.
@MainActor
final class HotkeyManager {
    /// Carbon-обработчик приходит как C-функция, у которой нет доступа к self. Отсюда
    /// статическая таблица: id хоткея → что делать. Помечено unsafe, потому что компилятор
    /// не может доказать потокобезопасность, но Carbon доставляет события хоткеев строго
    /// в главный run loop — фактический доступ однопоточный.
    private nonisolated(unsafe) static var actions: [UInt32: () -> Void] = [:]
    private nonisolated(unsafe) static var sharedHandler: EventHandlerRef?

    private static let signature: OSType = 0x434C5053  // 'CLPS'
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    /// Регистрирует комбинацию и возвращает её идентификатор — по нему потом снимать.
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) throws -> UInt32 {
        Self.installSharedHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw HotkeyError.registrationFailed(status)
        }

        registrations[id] = reference
        Self.actions[id] = action
        Log.hotkey.info("зарегистрирован хоткей \(combo.displayString, privacy: .public)")
        return id
    }

    func unregister(_ id: UInt32) {
        if let reference = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        Self.actions.removeValue(forKey: id)
    }

    func unregisterAll() {
        for id in Array(registrations.keys) { unregister(id) }
    }

    // deinit намеренно нет: обратиться отсюда к registrations нельзя (nonisolated deinit не
    // пускают к MainActor-состоянию), да и незачем — менеджер живёт столько же, сколько
    // процесс, а снимаем мы всё явно в applicationWillTerminate.

    private static func installSharedHandlerIfNeeded() {
        guard sharedHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                // Carbon доставляет это в главный run loop, изоляция фактически соблюдена.
                MainActor.assumeIsolated {
                    HotkeyManager.actions[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &sharedHandler
        )
    }
}

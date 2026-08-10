import AppKit

// Политику активации ставим ДО создания статус-айтема и до run(): иначе иконка приложения
// успевает мигнуть в доке. .accessory — агент без дока, но с правом показывать окна
// (LSUIElement в Info.plist делает то же самое, дублируем в коде для запуска из-под SPM,
// когда бандла ещё нет).
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Делегат держим в глобальной переменной: NSApplication.delegate — weak, локальная
// переменная уехала бы из памяти сразу после присваивания.
let delegate = AppDelegate()
app.delegate = delegate

app.run()

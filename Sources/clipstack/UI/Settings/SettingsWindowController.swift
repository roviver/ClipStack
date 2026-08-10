import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(content: some View) {
        // Пока открыты настройки, приложение становится обычным.
        //
        // Без этого окно открывается ПОЗАДИ чужих: .accessory-приложение системой не
        // выводится на передний план, и ни activate(), ни AXRaise этого не меняют —
        // пользователь жмёт «Настройки» и думает, что ничего не произошло.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки clipstack"
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        // activate() сам по себе не пробивает: macOS не даёт фоновому приложению отобрать
        // фокус, если пользователь не взаимодействовал с ним напрямую. orderFrontRegardless
        // выводит окно вперёд независимо от того, активны мы или нет.
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        // Возвращаемся в фоновый режим, иначе в доке навсегда останется лишняя иконка.
        NSApp.setActivationPolicy(.accessory)
    }
}

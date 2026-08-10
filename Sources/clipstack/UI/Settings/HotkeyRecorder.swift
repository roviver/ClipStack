import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Поле записи горячей клавиши: клик — начать запись, следующее нажатие становится комбинацией.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { combo = $0 }
        view.combo = combo
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.combo = combo
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var combo: KeyCombo = .defaultShow
        var onCapture: ((KeyCombo) -> Void)?
        private var isRecording = false

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

        override func mouseDown(with event: NSEvent) {
            isRecording = true
            window?.makeFirstResponder(self)
            needsDisplay = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            needsDisplay = true
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            // Escape отменяет запись, не назначая комбинацию: иначе выйти из режима записи
            // можно было бы только назначив что-нибудь.
            if Int(event.keyCode) == kVK_Escape {
                isRecording = false
                window?.makeFirstResponder(nil)
                needsDisplay = true
                return
            }

            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Хоткей без модификаторов перехватил бы обычный ввод во всех приложениях сразу.
            guard !modifiers.isEmpty else { NSSound.beep(); return }

            let captured = KeyCombo(keyCode: UInt32(event.keyCode), cocoaModifiers: modifiers)
            combo = captured
            onCapture?(captured)
            isRecording = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let background = isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.controlBackgroundColor
            background.setFill()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()

            let text = isRecording ? "Нажми комбинацию…" : combo.displayString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: isRecording ? 10 : 12),
                .foregroundColor: NSColor.labelColor
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}

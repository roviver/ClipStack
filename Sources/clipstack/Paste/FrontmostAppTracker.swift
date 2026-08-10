import AppKit

/// Помнит, какое приложение было активным до того, как мы показали панель.
///
/// Панель объявлена .nonactivatingPanel и в теории фронт не забирает, но полагаться на это
/// нельзя: часть приложений теряет фокус сама, да и пользователь может кликнуть мимо.
/// Дешевле запомнить цель заранее, чем гадать потом.
@MainActor
final class FrontmostAppTracker {
    private(set) var target: NSRunningApplication?

    func capture() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        // Себя запоминать бессмысленно — вставлять надо в чужое окно.
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        target = frontmost
        Log.paste.debug("цель вставки: \(frontmost?.localizedName ?? "неизвестно", privacy: .public)")
    }

    func clear() {
        target = nil
    }

    /// Возвращает фокус запомненному приложению и ждёт, пока оно реально станет активным.
    /// Возвращает false, если не дождались — тогда вставлять некуда.
    func reactivate(timeout: TimeInterval = 0.4) async -> Bool {
        guard let target, !target.isTerminated else { return false }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            return true
        }

        target.activate(options: [])

        // Активация асинхронна: система переключает фронт через свой цикл событий, и послать
        // ⌘V сразу — значит попасть в старое окно или в пустоту.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                return true
            }
        }

        Log.paste.error("не дождались активации \(target.localizedName ?? "?", privacy: .public)")
        return false
    }
}

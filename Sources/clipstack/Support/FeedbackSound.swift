import AppKit

/// Короткий звук-подтверждение при захвате копии.
@MainActor
enum FeedbackSound {
    /// Системные звуки macOS. Берём из каталога, а не хардкодим список: на разных версиях
    /// системы набор отличается, а несуществующее имя дало бы тишину без всякого объяснения.
    static let available: [String] = {
        let directory = "/System/Library/Sounds"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }()

    static let defaultName = available.contains("Pop") ? "Pop" : (available.first ?? "")

    /// Держим объект живым между вызовами.
    ///
    /// Две причины. Первая: play() асинхронный, и локальный NSSound может быть уничтожен
    /// раньше, чем звук доиграет. Вторая: NSSound(named:) отдаёт общий кешированный объект,
    /// поэтому повторный play() по ещё звучащему звуку возвращает false и молча ничего не
    /// делает — его нужно сначала остановить.
    private static var current: NSSound?

    static func play(named name: String) {
        if current?.name != name {
            current = NSSound(named: name)
        }
        guard let sound = current else {
            Log.app.error("звук '\(name, privacy: .public)' не найден")
            return
        }

        // Копии могут идти пачкой; накладывающиеся сигналы звучат как треск.
        if sound.isPlaying {
            sound.stop()
        }
        if sound.play() {
            Log.app.debug("звук '\(name, privacy: .public)' проигран")
        } else {
            Log.app.error("звук '\(name, privacy: .public)' не проигрался")
        }
    }
}

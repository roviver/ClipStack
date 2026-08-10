import Foundation

/// Связывает монитор буфера с хранилищем. Единственное место, где «поймали копию»
/// превращается в «записали в историю».
@MainActor
final class HistoryService {
    let repository: ClipRepository
    private let monitor: PasteboardMonitor
    private var insertsSinceTrim = 0

    /// Подрезать историю на каждой вставке расточительно: DELETE с подзапросом ради одной
    /// лишней строки. Раз в двадцать копий история переполнится максимум на 19 записей.
    private let trimEvery = 20

    var historyLimit: Int = 1000
    var pollInterval: TimeInterval = 0.3
    var soundEnabled = false
    var soundName = FeedbackSound.defaultName

    var ignoredBundleIDs: Set<String> {
        get { monitor.filter.ignoredBundleIDs }
        set { monitor.filter.ignoredBundleIDs = newValue }
    }

    init(repository: ClipRepository, monitor: PasteboardMonitor) {
        self.repository = repository
        self.monitor = monitor
        monitor.onCapture = { [weak self] draft in
            self?.capture(draft)
        }
    }

    func start() {
        monitor.start(interval: pollInterval)
    }

    /// Применить изменившиеся настройки на лету, без перезапуска приложения.
    func applyLimitNow() {
        do {
            try repository.trim(keeping: historyLimit)
        } catch {
            Log.storage.error("не удалось подрезать историю: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        monitor.stop()
    }

    /// Сообщить, что в буфер писали мы сами (при вставке из истории).
    func acknowledgeOwnWrite() {
        monitor.acknowledgeOwnWrite()
    }

    private func capture(_ draft: ClipDraft) {
        do {
            let id = try repository.insert(draft)
            Log.clipboard.debug("сохранено #\(id): \(draft.kind.rawValue, privacy: .public), \(draft.byteSize) Б")

            if soundEnabled {
                FeedbackSound.play(named: soundName)
            }

            insertsSinceTrim += 1
            if insertsSinceTrim >= trimEvery {
                insertsSinceTrim = 0
                try repository.trim(keeping: historyLimit)
            }
        } catch {
            Log.clipboard.error("не удалось сохранить копию: \(String(describing: error), privacy: .public)")
        }
    }
}

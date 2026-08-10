import Foundation
import SwiftUI

/// Настройки приложения поверх UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let historyLimit = "historyLimit"
        static let showHotkey = "showHotkey"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let pollInterval = "pollInterval"
        static let soundEnabled = "soundEnabled"
        static let soundName = "soundName"
    }

    private let defaults: UserDefaults

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }

    @Published var showHotkey: KeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(showHotkey) else { return }
            defaults.set(data, forKey: Key.showHotkey)
        }
    }

    @Published var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Key.ignoredBundleIDs) }
    }

    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Key.pollInterval) }
    }

    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    @Published var soundName: String {
        didSet { defaults.set(soundName, forKey: Key.soundName) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedLimit = defaults.integer(forKey: Key.historyLimit)
        // integer(forKey:) отдаёт 0 и когда ключа нет, и когда там честный ноль. Ноль как
        // размер истории бессмысленен, так что трактуем его как «не задано».
        historyLimit = storedLimit > 0 ? storedLimit : 1000

        if let data = defaults.data(forKey: Key.showHotkey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            showHotkey = combo
        } else {
            showHotkey = .defaultShow
        }

        ignoredBundleIDs = defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? []

        let storedInterval = defaults.double(forKey: Key.pollInterval)
        pollInterval = storedInterval > 0 ? storedInterval : 0.3

        // Звук по умолчанию выключен: непрошеное пиканье на каждое ⌘C раздражает сильнее,
        // чем радует. Кому нужно — включит.
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        soundName = defaults.string(forKey: Key.soundName) ?? FeedbackSound.defaultName
    }
}

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?
    @State private var historyCount: Int = 0

    var onHotkeyChanged: (KeyCombo) -> Void
    var onClearHistory: (Bool) -> Void
    var onCountRequested: () -> Int

    var body: some View {
        Form {
            Section("Горячая клавиша") {
                LabeledContent("Показать историю") {
                    HotkeyRecorder(combo: Binding(
                        get: { preferences.showHotkey },
                        set: { combo in
                            preferences.showHotkey = combo
                            onHotkeyChanged(combo)
                        }
                    ))
                    .frame(width: 130, height: 24)
                }
            }

            Section("История") {
                LabeledContent("Хранить записей") {
                    HStack(spacing: 6) {
                        TextField("", value: $preferences.historyLimit, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $preferences.historyLimit, in: 50...20000, step: 50)
                            .labelsHidden()
                    }
                }
                Text("Закреплённые записи не вытесняются и в лимит не входят.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Сейчас в истории") {
                    Text("\(historyCount)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Очистить, кроме закреплённых") { onClearHistory(true); refreshCount() }
                    Button("Очистить всё") { onClearHistory(false); refreshCount() }
                        .foregroundStyle(.red)
                }
            }

            Section("Звук") {
                Toggle("Звук при копировании", isOn: $preferences.soundEnabled)
                LabeledContent("Звук") {
                    HStack(spacing: 8) {
                        Picker("", selection: $preferences.soundName) {
                            ForEach(FeedbackSound.available, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        Button("Прослушать") { FeedbackSound.play(named: preferences.soundName) }
                    }
                }
                .disabled(!preferences.soundEnabled)
            }

            Section("Запуск") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if !LoginItem.setEnabled(enabled) {
                            // Возвращаем переключатель назад: показывать «включено», когда
                            // система отказала, — прямая ложь пользователю.
                            launchAtLogin = LoginItem.isEnabled
                        }
                        loginNote = LoginItem.statusDescription
                    }
                if let loginNote {
                    Text("Состояние: \(loginNote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Не запоминать копии из этих приложений") {
                IgnoredAppsList(bundleIDs: $preferences.ignoredBundleIDs)
            }

            Section("Приватность") {
                Text("""
                    Копии, помеченные приложением как секретные, не сохраняются никогда — \
                    так делают менеджеры паролей. История лежит только на этом компьютере \
                    и никуда не отправляется.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear { refreshCount() }
    }

    private func refreshCount() {
        historyCount = onCountRequested()
    }
}

/// Список приложений, копии из которых игнорируются.
private struct IgnoredAppsList: View {
    @Binding var bundleIDs: [String]
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if bundleIDs.isEmpty {
                Text("Список пуст")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(bundleIDs, id: \.self, selection: $selection) { bundleID in
                    HStack(spacing: 6) {
                        if let icon = appIcon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(appName(for: bundleID))
                        Text(bundleID).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 110)
            }

            HStack {
                Button("Добавить…") { addApp() }
                Button("Убрать") {
                    guard let selection else { return }
                    bundleIDs.removeAll { $0 == selection }
                    self.selection = nil
                }
                .disabled(selection == nil)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            if !bundleIDs.contains(id) { bundleIDs.append(id) }
        }
    }

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = appURL(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

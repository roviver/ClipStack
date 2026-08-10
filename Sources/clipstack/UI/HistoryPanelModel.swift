import AppKit
import Combine

@MainActor
final class HistoryPanelModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var query: String = ""
    @Published var activeKind: ClipKind?
    @Published var showPinnedOnly: Bool = false
    @Published private(set) var selectedIndex: Int = 0

    private let repository: ClipRepository

    init(repository: ClipRepository) {
        self.repository = repository
    }

    var selectedItem: ClipItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func reload(resetSelection: Bool = true) {
        do {
            items = try repository.items(ClipQuery(
                limit: 200,
                kind: activeKind,
                search: query.isEmpty ? nil : query,
                pinnedOnly: showPinnedOnly
            ))
        } catch {
            Log.ui.error("не удалось прочитать историю: \(String(describing: error), privacy: .public)")
            items = []
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = 0
        }
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        // Без зацикливания: упёрся в край — стоишь на краю. Перескок с последнего элемента
        // на первый в списке из двух сотен строк дезориентирует.
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        togglePin(item)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func togglePin(_ item: ClipItem) {
        do {
            try repository.setPinned(!item.isPinned, id: item.id)
            reload(resetSelection: false)
        } catch {
            Log.ui.error("не удалось закрепить: \(String(describing: error), privacy: .public)")
        }
    }

    func delete(_ item: ClipItem) {
        do {
            try repository.delete(id: item.id)
            reload(resetSelection: false)
        } catch {
            Log.ui.error("не удалось удалить: \(String(describing: error), privacy: .public)")
        }
    }
}

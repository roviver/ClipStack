import SwiftUI

struct ClipListView: View {
    @ObservedObject var model: HistoryPanelModel
    @FocusState private var searchFocused: Bool

    var onActivate: (ClipItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            FilterBar(model: model)
            Divider()
            if model.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 420, height: 520)
        .background(.ultraThinMaterial)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск по истории", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: model.query) { _, _ in model.reload() }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(item: item, index: index, isSelected: index == model.selectedIndex)
                            .id(item.id)
                            .onTapGesture { onActivate(item) }
                            .contextMenu {
                                Button(item.isPinned ? "Открепить" : "Закрепить") {
                                    model.togglePin(item)
                                }
                                Button("Удалить", role: .destructive) {
                                    model.delete(item)
                                }
                            }
                    }
                }
                .padding(6)
            }
            // Выделение двигается с клавиатуры, поэтому список должен сам догонять его,
            // иначе стрелка вниз уводит выбор за пределы видимой области.
            .onChange(of: model.selectedIndex) { _, index in
                guard model.items.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(model.items[index].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "История пуста" : "Ничего не найдено")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

/// Фильтры по типу содержимого и по закреплённым.
struct FilterBar: View {
    @ObservedObject var model: HistoryPanelModel

    var body: some View {
        HStack(spacing: 4) {
            chip(title: "Все", symbol: "square.grid.2x2", isActive: isShowingAll) {
                model.activeKind = nil
                model.showPinnedOnly = false
                model.reload()
            }

            chip(title: "Закреплённые", symbol: "pin.fill", isActive: model.showPinnedOnly) {
                model.showPinnedOnly = true
                model.activeKind = nil
                model.reload()
            }

            Divider().frame(height: 14)

            ForEach(ClipKind.allCases, id: \.self) { kind in
                chip(
                    title: kind.title,
                    symbol: kind.symbolName,
                    isActive: model.activeKind == kind && !model.showPinnedOnly
                ) {
                    model.activeKind = kind
                    model.showPinnedOnly = false
                    model.reload()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var isShowingAll: Bool {
        model.activeKind == nil && !model.showPinnedOnly
    }

    private func chip(title: String, symbol: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isActive ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

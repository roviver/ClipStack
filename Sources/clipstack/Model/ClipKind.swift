import Foundation

enum ClipKind: String, CaseIterable, Sendable {
    case text
    case link
    case image
    case file
    case color

    var title: String {
        switch self {
        case .text: "Текст"
        case .link: "Ссылки"
        case .image: "Картинки"
        case .file: "Файлы"
        case .color: "Цвета"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}

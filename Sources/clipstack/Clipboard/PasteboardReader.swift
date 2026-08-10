import AppKit
import CryptoKit
import Foundation

/// Достаёт из буфера то, что стоит сохранить, и определяет тип.
struct PasteboardReader {
    func read(_ pasteboard: NSPasteboard) -> ClipDraft? {
        // Порядок проверок = приоритет типов, и он важен. Копия файла в Finder кладёт в буфер
        // и file URL, и строку с путём; копия картинки из Finder — тоже file URL. Начни мы с
        // текста, всё это осело бы в истории как невнятные строки.
        if let draft = readFiles(pasteboard) { return draft }
        if let draft = readImage(pasteboard) { return draft }
        if let draft = readColor(pasteboard) { return draft }
        return readText(pasteboard)
    }

    // MARK: - Типы

    private func readFiles(_ pasteboard: NSPasteboard) -> ClipDraft? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return nil }

        let paths = urls.map(\.path).joined(separator: "\n")
        return ClipDraft(
            kind: .file,
            text: paths,
            imageData: nil,
            contentHash: hash(of: Data(paths.utf8)),
            byteSize: paths.utf8.count
        )
    }

    private func readImage(_ pasteboard: NSPasteboard) -> ClipDraft? {
        guard let raw = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else {
            return nil
        }
        // Нормализуем в PNG: буфер обычно отдаёт TIFF, а он весит в разы больше при том же
        // содержимом, и хеш от TIFF нестабилен между источниками одной и той же картинки.
        guard let png = NSBitmapImageRep(data: raw)?.representation(using: .png, properties: [:]) else {
            return nil
        }
        return ClipDraft(
            kind: .image,
            text: nil,
            imageData: png,
            contentHash: hash(of: png),
            byteSize: png.count
        )
    }

    private func readColor(_ pasteboard: NSPasteboard) -> ClipDraft? {
        guard pasteboard.availableType(from: [.color]) != nil,
              let color = NSColor(from: pasteboard),
              let srgb = color.usingColorSpace(.sRGB) else { return nil }

        let hex = String(
            format: "#%02X%02X%02X",
            Int(round(srgb.redComponent * 255)),
            Int(round(srgb.greenComponent * 255)),
            Int(round(srgb.blueComponent * 255))
        )
        return ClipDraft(
            kind: .color,
            text: hex,
            imageData: nil,
            contentHash: hash(of: Data(hex.utf8)),
            byteSize: hex.utf8.count
        )
    }

    private func readText(_ pasteboard: NSPasteboard) -> ClipDraft? {
        guard let string = pasteboard.string(forType: .string) else { return nil }
        // Пустую строку и голые пробелы в историю не пускаем — мусор, который забивает список.
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return ClipDraft(
            kind: isLink(string) ? .link : .text,
            text: string,
            imageData: nil,
            contentHash: hash(of: Data(string.utf8)),
            byteSize: string.utf8.count
        )
    }

    // MARK: - Вспомогательное

    private func isLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Многострочный текст со ссылкой внутри — это всё-таки текст, а не ссылка.
        guard !trimmed.contains(where: \.isNewline), trimmed.count < 2048 else { return false }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "ssh", "mailto"].contains(scheme) && url.host?.isEmpty == false
    }

    private func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

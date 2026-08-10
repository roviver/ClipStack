import AppKit

/// Кладёт элемент истории обратно в системный буфер.
struct PasteboardWriter {
    @discardableResult
    func write(_ item: ClipItem, pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()

        switch item.kind {
        case .image:
            guard let url = item.blobURL, let data = try? Data(contentsOf: url) else {
                Log.paste.error("блоб картинки не найден: \(item.blobName ?? "nil", privacy: .public)")
                return false
            }
            return pasteboard.setData(data, forType: .png)

        case .file:
            let urls = (item.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            guard !urls.isEmpty else { return false }
            return pasteboard.writeObjects(urls)

        case .color:
            guard let hex = item.text, let color = NSColor(hex: hex) else { return false }
            return pasteboard.writeObjects([color])

        case .text, .link:
            guard let text = item.text else { return false }
            return pasteboard.setString(text, forType: .string)
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

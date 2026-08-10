import AppKit
import SwiftUI

struct ClipRowView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(2)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                HStack(spacing: 6) {
                    if let app = item.source?.appName {
                        Text(app)
                    }
                    Text(relativeTime)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            }

            Spacer(minLength: 4)

            // Ярлык для быстрого выбора: первые девять строк жмутся ⌘1…⌘9.
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let url = item.blobURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                symbolPreview
            }
        case .color:
            RoundedRectangle(cornerRadius: 4)
                .fill(swatchColor)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        default:
            symbolPreview
        }
    }

    private var symbolPreview: some View {
        Image(systemName: item.kind.symbolName)
            .font(.system(size: 14))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.secondary.opacity(0.1))
            )
    }

    private var swatchColor: Color {
        guard let hex = item.text else { return .gray }
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private var title: String {
        switch item.kind {
        case .image:
            return "Картинка \(byteSizeText)"
        case .file:
            // В списке нужны имена файлов, а не полные пути: путь /Users/... съедает всю строку.
            let names = (item.text ?? "").split(separator: "\n").map {
                URL(fileURLWithPath: String($0)).lastPathComponent
            }
            return names.joined(separator: ", ")
        default:
            let raw = item.text ?? ""
            // Схлопываем переводы строк: иначе одна многострочная копия занимает пол-списка.
            return raw
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var byteSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.localizedString(for: item.updatedAt, relativeTo: Date())
    }
}

import Foundation

struct ClipSource: Sendable, Hashable {
    let bundleID: String
    let appName: String
}

/// Запись истории, как она лежит в базе.
struct ClipItem: Identifiable, Sendable, Hashable {
    let id: Int64
    let kind: ClipKind
    /// Для .image — nil. Для остальных типов это и содержимое, и то, по чему идёт поиск.
    /// Для .file — пути, по одному на строку.
    let text: String?
    /// Имя файла в Paths.blobsDirectory, только для .image.
    let blobName: String?
    let contentHash: String
    let source: ClipSource?
    let createdAt: Date
    let updatedAt: Date
    let isPinned: Bool
    let byteSize: Int

    var blobURL: URL? {
        blobName.map { Paths.blobsDirectory.appendingPathComponent($0) }
    }
}

/// То, что прочитали из буфера, но ещё не записали в базу.
struct ClipDraft: Sendable {
    let kind: ClipKind
    let text: String?
    let imageData: Data?
    let contentHash: String
    let byteSize: Int
    var source: ClipSource?
}

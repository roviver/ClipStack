import Foundation

/// Картинки на диске. Имя файла — это content hash, поэтому одинаковые картинки физически
/// хранятся один раз, а повторная копия того же скриншота ничего не пишет.
struct BlobStore {
    func save(_ data: Data, hash: String) throws -> String {
        let name = "\(hash).png"
        let url = Paths.blobsDirectory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return name }
        try data.write(to: url, options: .atomic)
        return name
    }

    func delete(_ name: String) {
        let url = Paths.blobsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    /// Файлы, на которые больше не ссылается ни одна запись. Появляются, если приложение
    /// умерло между записью блоба и коммитом в базу.
    func removeOrphans(referenced: Set<String>) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Paths.blobsDirectory.path) else { return }
        var removed = 0
        for name in names where !referenced.contains(name) {
            try? fm.removeItem(at: Paths.blobsDirectory.appendingPathComponent(name))
            removed += 1
        }
        if removed > 0 {
            Log.storage.info("подчищено осиротевших блобов: \(removed)")
        }
    }
}

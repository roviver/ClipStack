import Foundation

enum Paths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("clipstack", isDirectory: true)
    }()

    static var databaseFile: URL {
        supportDirectory.appendingPathComponent("clipstack.sqlite")
    }

    /// Картинки лежат файлами на диске, а в базе только путь. Иначе база пухнет до гигабайтов:
    /// один скриншот ретины это 5-15 МБ, а история их копит сотнями.
    static var blobsDirectory: URL {
        supportDirectory.appendingPathComponent("blobs", isDirectory: true)
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    }
}

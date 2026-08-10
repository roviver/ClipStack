import Foundation

struct ClipQuery {
    var limit: Int = 200
    var kind: ClipKind?
    var search: String?
    var pinnedOnly: Bool = false
}

/// Доступ к истории. Живёт на главном потоке осознанно: запросы идут по таблице,
/// ограниченной лимитом истории (порядка тысячи строк), это десятки микросекунд.
/// KNOWN-V1: если история вырастет на порядок или появятся тормоза UI — выносить в actor
/// с отдельным соединением, а поиск переводить на FTS5 с триграммным токенайзером.
@MainActor
final class ClipRepository {
    private let db: Database
    private let blobs: BlobStore

    init(database: Database, blobs: BlobStore = BlobStore()) {
        self.db = database
        self.blobs = blobs
    }

    // MARK: - Запись

    /// Возвращает id записи. Повторная копия того же содержимого не создаёт дубль,
    /// а поднимает существующую запись наверх — это ожидаемое поведение менеджера буфера.
    @discardableResult
    func insert(_ draft: ClipDraft) throws -> Int64 {
        var blobName: String?
        if draft.kind == .image, let data = draft.imageData {
            blobName = try blobs.save(data, hash: draft.contentHash)
        }

        let now = Date().timeIntervalSince1970
        let statement = try db.prepare("""
            INSERT INTO clips
                (kind, text, blob_name, content_hash, source_bundle_id, source_app_name,
                 created_at, updated_at, byte_size)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, ?8)
            ON CONFLICT(content_hash) DO UPDATE SET
                updated_at = excluded.updated_at,
                source_bundle_id = COALESCE(excluded.source_bundle_id, clips.source_bundle_id),
                source_app_name  = COALESCE(excluded.source_app_name, clips.source_app_name)
            RETURNING id
            """)
        statement
            .bind(1, draft.kind.rawValue)
            .bind(2, draft.text)
            .bind(3, blobName)
            .bind(4, draft.contentHash)
            .bind(5, draft.source?.bundleID)
            .bind(6, draft.source?.appName)
            .bind(7, now)
            .bind(8, Int64(draft.byteSize))

        guard try statement.step() else {
            throw DatabaseError.step("INSERT ... RETURNING не вернул id")
        }
        return statement.int64(0)
    }

    // MARK: - Чтение

    func items(_ query: ClipQuery = ClipQuery()) throws -> [ClipItem] {
        var conditions: [String] = []
        if query.kind != nil { conditions.append("kind = :kind") }
        if query.pinnedOnly { conditions.append("is_pinned = 1") }
        // Поиск подстрокой, а не префиксом: пользователь помнит кусок из середины строки
        // чаще, чем её начало. Индекс тут не работает, но скан тысячи строк бесплатен.
        if query.search?.isEmpty == false { conditions.append("text LIKE :search ESCAPE '\\'") }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let statement = try db.prepare("""
            SELECT id, kind, text, blob_name, content_hash, source_bundle_id, source_app_name,
                   created_at, updated_at, is_pinned, byte_size
            FROM clips
            \(whereClause)
            ORDER BY updated_at DESC
            LIMIT :limit
            """)

        if let kind = query.kind {
            statement.bind(statement.parameterIndex(":kind"), kind.rawValue)
        }
        if let search = query.search, !search.isEmpty {
            statement.bind(statement.parameterIndex(":search"), "%\(escapeLike(search))%")
        }
        statement.bind(statement.parameterIndex(":limit"), Int64(query.limit))

        var result: [ClipItem] = []
        while try statement.step() {
            result.append(decode(statement))
        }
        return result
    }

    func item(id: Int64) throws -> ClipItem? {
        let statement = try db.prepare("""
            SELECT id, kind, text, blob_name, content_hash, source_bundle_id, source_app_name,
                   created_at, updated_at, is_pinned, byte_size
            FROM clips WHERE id = ?1
            """)
        statement.bind(1, id)
        return try statement.step() ? decode(statement) : nil
    }

    func count() throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM clips")
        guard try statement.step() else { return 0 }
        return Int(statement.int64(0))
    }

    // MARK: - Изменение

    func setPinned(_ pinned: Bool, id: Int64) throws {
        let statement = try db.prepare("UPDATE clips SET is_pinned = ?1 WHERE id = ?2")
        statement.bind(1, pinned).bind(2, id)
        try statement.run()
    }

    func delete(id: Int64) throws {
        if let blobName = try item(id: id)?.blobName {
            blobs.delete(blobName)
        }
        let statement = try db.prepare("DELETE FROM clips WHERE id = ?1")
        statement.bind(1, id)
        try statement.run()
    }

    /// Оставляет `limit` последних незакреплённых записей. Пины не вытесняются никогда —
    /// иначе смысл закрепления теряется.
    func trim(keeping limit: Int) throws {
        try db.transaction {
            let doomed = try db.prepare("""
                SELECT blob_name FROM clips
                WHERE is_pinned = 0 AND blob_name IS NOT NULL
                  AND id NOT IN (
                      SELECT id FROM clips WHERE is_pinned = 0
                      ORDER BY updated_at DESC LIMIT ?1
                  )
                """)
            doomed.bind(1, Int64(limit))
            var blobNames: [String] = []
            while try doomed.step() {
                if let name = doomed.string(0) { blobNames.append(name) }
            }

            let delete = try db.prepare("""
                DELETE FROM clips
                WHERE is_pinned = 0
                  AND id NOT IN (
                      SELECT id FROM clips WHERE is_pinned = 0
                      ORDER BY updated_at DESC LIMIT ?1
                  )
                """)
            delete.bind(1, Int64(limit))
            try delete.run()

            for name in blobNames { blobs.delete(name) }
        }
    }

    func clear(keepPinned: Bool) throws {
        try db.transaction {
            let sql = keepPinned ? "DELETE FROM clips WHERE is_pinned = 0" : "DELETE FROM clips"
            try db.execute(sql)
            let referenced = try referencedBlobNames()
            blobs.removeOrphans(referenced: referenced)
        }
    }

    func referencedBlobNames() throws -> Set<String> {
        let statement = try db.prepare("SELECT blob_name FROM clips WHERE blob_name IS NOT NULL")
        var names: Set<String> = []
        while try statement.step() {
            if let name = statement.string(0) { names.insert(name) }
        }
        return names
    }

    // MARK: - Внутреннее

    private func decode(_ s: Statement) -> ClipItem {
        let bundleID = s.string(5)
        let appName = s.string(6)
        return ClipItem(
            id: s.int64(0),
            kind: ClipKind(rawValue: s.string(1) ?? "") ?? .text,
            text: s.string(2),
            blobName: s.string(3),
            contentHash: s.string(4) ?? "",
            source: bundleID.map { ClipSource(bundleID: $0, appName: appName ?? $0) },
            createdAt: Date(timeIntervalSince1970: s.double(7)),
            updatedAt: Date(timeIntervalSince1970: s.double(8)),
            isPinned: s.bool(9),
            byteSize: Int(s.int64(10))
        )
    }

    /// В LIKE символы % и _ — подстановочные. Пользователь, ищущий «50%», имеет в виду
    /// именно знак процента, а не «что угодно».
    private func escapeLike(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

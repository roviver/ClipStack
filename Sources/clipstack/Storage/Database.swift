import Foundation
import SQLite3

enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case prepare(sql: String, message: String)
    case step(String)

    var description: String {
        switch self {
        case .open(let m): "не удалось открыть базу: \(m)"
        case .prepare(let sql, let m): "не удалось подготовить запрос (\(m)): \(sql)"
        case .step(let m): "ошибка выполнения: \(m)"
        }
    }
}

/// SQLite требует сказать, что делать с переданным буфером. TRANSIENT = «скопируй себе»:
/// без него SQLite сохранит указатель на память Swift-строки, которая умрёт сразу после bind,
/// и в базу приедет мусор.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Тонкая обёртка над системным SQLite. Внешних зависимостей не берём: без Xcode каждая
/// из них — лишняя точка отказа в сборочном скрипте, а нужен нам десяток запросов.
final class Database {
    private var handle: OpaquePointer?

    init(path: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "неизвестная ошибка"
            sqlite3_close_v2(handle)
            throw DatabaseError.open(message)
        }
        // WAL: приложение пишет в базу постоянно (каждая копия), при жёстком завершении
        // журнал отката оставил бы базу битой.
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changedRowCount: Int32 { sqlite3_changes(handle) }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "неизвестная ошибка"
            sqlite3_free(errorPointer)
            throw DatabaseError.step(message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        try Statement(db: handle, sql: sql)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Миграции

    /// Порядок менять нельзя, только дописывать в конец: индекс элемента = номер версии схемы.
    private static let migrations: [String] = [
        """
        CREATE TABLE clips (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            kind             TEXT    NOT NULL,
            text             TEXT,
            blob_name        TEXT,
            content_hash     TEXT    NOT NULL UNIQUE,
            source_bundle_id TEXT,
            source_app_name  TEXT,
            created_at       REAL    NOT NULL,
            updated_at       REAL    NOT NULL,
            is_pinned        INTEGER NOT NULL DEFAULT 0,
            byte_size        INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX idx_clips_updated ON clips(updated_at DESC);
        CREATE INDEX idx_clips_pinned ON clips(is_pinned DESC, updated_at DESC);
        """
    ]

    private func migrate() throws {
        var version = try userVersion()
        guard version < Self.migrations.count else { return }

        while version < Self.migrations.count {
            let sql = Self.migrations[Int(version)]
            try execute("BEGIN IMMEDIATE")
            do {
                try execute(sql)
                version += 1
                // PRAGMA не принимает параметры-плейсхолдеры, только литерал. Значение
                // здесь — наш собственный Int32, не пользовательский ввод.
                try execute("PRAGMA user_version = \(version)")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
            Log.storage.info("схема мигрирована до версии \(version)")
        }
    }

    private func userVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        guard try statement.step() else { return 0 }
        return Int32(statement.int64(0))
    }
}

/// Подготовленный запрос. Индексы для bind начинаются с 1, для чтения колонок — с 0.
/// Это правило SQLite, не опечатка.
final class Statement {
    private var stmt: OpaquePointer?
    private let db: OpaquePointer?

    init(db: OpaquePointer?, sql: String) throws {
        self.db = db
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "неизвестная ошибка"
            throw DatabaseError.prepare(sql: sql, message: message)
        }
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    /// Индекс именованного параметра (":limit"). Возвращает 0, если такого нет в запросе —
    /// bind по нулевому индексу SQLite молча игнорирует, поэтому опечатка в имени приведёт
    /// к «параметр не подставился», а не к ошибке.
    func parameterIndex(_ name: String) -> Int32 {
        sqlite3_bind_parameter_index(stmt, name)
    }

    @discardableResult
    func bind(_ index: Int32, _ value: String?) -> Statement {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
        return self
    }

    @discardableResult
    func bind(_ index: Int32, _ value: Int64) -> Statement {
        sqlite3_bind_int64(stmt, index, value)
        return self
    }

    @discardableResult
    func bind(_ index: Int32, _ value: Double) -> Statement {
        sqlite3_bind_double(stmt, index, value)
        return self
    }

    @discardableResult
    func bind(_ index: Int32, _ value: Bool) -> Statement {
        sqlite3_bind_int64(stmt, index, value ? 1 : 0)
        return self
    }

    /// true — прочитана очередная строка, false — данные кончились.
    @discardableResult
    func step() throws -> Bool {
        let code = sqlite3_step(stmt)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "код \(code)"
            throw DatabaseError.step(message)
        }
    }

    func run() throws {
        _ = try step()
    }

    func string(_ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }

    func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(stmt, column)
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(stmt, column)
    }

    func bool(_ column: Int32) -> Bool {
        sqlite3_column_int64(stmt, column) != 0
    }
}

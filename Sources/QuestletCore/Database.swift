import Foundation
import CSQLite

public final class Database {
    private var db: OpaquePointer?
    public let url: URL
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Questlet/questlet.sqlite")
    }
    public init(url: URL = Database.defaultURL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw InputError("로컬 DB를 열 수 없습니다.") }
        sqlite3_busy_timeout(db, 3000)
        try run("PRAGMA journal_mode=WAL")
        try run("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK (id = 1), data BLOB NOT NULL)")
    }
    deinit { sqlite3_close(db) }
    private func run(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw InputError("DB 처리 실패: \(String(cString: sqlite3_errmsg(db)))") }
    }
    public func load() throws -> Snapshot {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM app_state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw InputError("DB 조회 실패") }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return Snapshot() }
        guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw InputError("DB 데이터를 읽을 수 없습니다.") }
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        guard value.version == 1 else { throw InputError("지원하지 않는 DB 버전입니다. 데이터를 보존하고 앱을 업데이트하세요.") }
        return value
    }
    public func save(_ value: Snapshot) throws {
        // ponytail: 개인 작업 목록 규모에서 snapshot 한 건을 원자 저장한다. 대량 기록이면 행별 저장으로 전환.
        let data = try JSONEncoder().encode(value)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO app_state(id,data) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data", -1, &statement, nil) == SQLITE_OK else { throw InputError("DB 저장 준비 실패") }
        defer { sqlite3_finalize(statement) }
        let code = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            return sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw InputError("로컬 저장에 실패했습니다. \(String(cString: sqlite3_errmsg(db)))") }
    }
}

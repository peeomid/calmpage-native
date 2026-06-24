import Foundation
import SQLite3

final class LibraryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    init(url: URL) throws {
        let sqlitePath = url.lastPathComponent == ":memory:" ? ":memory:" : url.path
        if sqlitePath != ":memory:" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try check(sqlite3_open(sqlitePath, &db))
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    static func memory() throws -> LibraryStore {
        try LibraryStore(url: URL(fileURLWithPath: ":memory:"))
    }

    func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS roots (
          id TEXT PRIMARY KEY,
          path TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS files (
          id TEXT PRIMARY KEY,
          root_id TEXT NOT NULL,
          path TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          title TEXT NOT NULL,
          extension TEXT NOT NULL,
          size_bytes INTEGER NOT NULL,
          modified_at REAL NOT NULL,
          indexed_at REAL NOT NULL,
          UNIQUE(root_id, relative_path)
        );
        CREATE INDEX IF NOT EXISTS idx_files_title ON files(title);
        CREATE INDEX IF NOT EXISTS idx_files_relative_path ON files(relative_path);
        """)
    }

    func upsertRoot(_ root: RootFolder) throws {
        try locked {
            try withStatement("""
        INSERT INTO roots (id, path, name, created_at)
        VALUES (?1, ?2, ?3, ?4)
        ON CONFLICT(id) DO UPDATE SET path = excluded.path, name = excluded.name
        """) { statement in
            bindText(statement, 1, root.id)
            bindText(statement, 2, root.url.path)
            bindText(statement, 3, root.name)
            sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
            try stepDone(statement)
        }
        }
    }

    func roots() throws -> [RootFolder] {
        try locked {
            try query("SELECT id, path, name FROM roots ORDER BY name ASC") { statement in
                let path = columnText(statement, 1)
                return RootFolder(id: columnText(statement, 0), url: URL(fileURLWithPath: path), name: columnText(statement, 2))
            }
        }
    }

    func removeRootsNotIn(_ rootIDs: Set<String>) throws {
        try locked {
            if rootIDs.isEmpty {
                try exec("DELETE FROM files")
                try exec("DELETE FROM roots")
                return
            }
            let placeholders = rootIDs.enumerated().map { "?\($0.offset + 1)" }.joined(separator: ",")
            let ids = Array(rootIDs).sorted()
            try withStatement("DELETE FROM files WHERE root_id NOT IN (\(placeholders))") { statement in
                for (index, id) in ids.enumerated() { bindText(statement, Int32(index + 1), id) }
                try stepDone(statement)
            }
            try withStatement("DELETE FROM roots WHERE id NOT IN (\(placeholders))") { statement in
                for (index, id) in ids.enumerated() { bindText(statement, Int32(index + 1), id) }
                try stepDone(statement)
            }
        }
    }

    func upsertFiles(_ files: [MarkdownFile], rootID: String) throws {
        try locked {
            try exec("BEGIN TRANSACTION")
            do {
                for file in files {
                    try upsertFileUnlocked(file, rootID: rootID)
                }
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    func upsertFile(_ file: MarkdownFile, rootID: String) throws {
        try locked {
            try upsertFileUnlocked(file, rootID: rootID)
        }
    }

    private func upsertFileUnlocked(_ file: MarkdownFile, rootID: String) throws {
        try withStatement("""
        INSERT INTO files (id, root_id, path, relative_path, title, extension, size_bytes, modified_at, indexed_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
        ON CONFLICT(root_id, relative_path) DO UPDATE SET
          path = excluded.path,
          title = excluded.title,
          extension = excluded.extension,
          size_bytes = excluded.size_bytes,
          modified_at = excluded.modified_at,
          indexed_at = excluded.indexed_at
        """) { statement in
            bindText(statement, 1, file.id)
            bindText(statement, 2, rootID)
            bindText(statement, 3, file.url.path)
            bindText(statement, 4, file.relativePath)
            bindText(statement, 5, file.title)
            bindText(statement, 6, file.url.pathExtension.lowercased())
            sqlite3_bind_int64(statement, 7, file.sizeBytes)
            sqlite3_bind_double(statement, 8, file.modifiedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 9, Date().timeIntervalSince1970)
            try stepDone(statement)
        }
    }

    func searchFiles(query searchText: String, limit: Int) throws -> [MarkdownFile] {
        try locked {
            let pattern = "%\(searchText.lowercased())%"
            let normalizedPattern = "%\(Self.normalizedSearchText(searchText))%"
            return try query("""
        SELECT id, path, relative_path, title, size_bytes, modified_at FROM files
        WHERE lower(title) LIKE ?1
           OR lower(relative_path) LIKE ?1
           OR lower(replace(replace(replace(title, ' ', ''), '-', ''), '_', '')) LIKE ?2
           OR lower(replace(replace(replace(relative_path, ' ', ''), '-', ''), '_', '')) LIKE ?2
        ORDER BY relative_path ASC
        LIMIT ?3
        """) { statement in
            bindText(statement, 1, pattern)
            bindText(statement, 2, normalizedPattern)
            sqlite3_bind_int(statement, 3, Int32(limit))
        } map: { statement in
            markdownFile(from: statement)
        }
        }
    }

    func searchFiles(query searchText: String, rootIDs: Set<String>, limit: Int) throws -> [MarkdownFile] {
        guard !rootIDs.isEmpty else { return [] }
        return try locked {
            let ids = Array(rootIDs).sorted()
            let placeholders = ids.enumerated().map { "?\($0.offset + 3)" }.joined(separator: ",")
            let pattern = "%\(searchText.lowercased())%"
            let normalizedPattern = "%\(Self.normalizedSearchText(searchText))%"
            return try query("""
        SELECT id, path, relative_path, title, size_bytes, modified_at FROM files
        WHERE (
            lower(title) LIKE ?1
            OR lower(relative_path) LIKE ?1
            OR lower(replace(replace(replace(title, ' ', ''), '-', ''), '_', '')) LIKE ?2
            OR lower(replace(replace(replace(relative_path, ' ', ''), '-', ''), '_', '')) LIKE ?2
        ) AND root_id IN (\(placeholders))
        ORDER BY relative_path ASC
        LIMIT ?\(ids.count + 3)
        """) { statement in
            bindText(statement, 1, pattern)
            bindText(statement, 2, normalizedPattern)
            for (index, id) in ids.enumerated() { bindText(statement, Int32(index + 3), id) }
            sqlite3_bind_int(statement, Int32(ids.count + 3), Int32(limit))
        } map: { statement in
            markdownFile(from: statement)
        }
        }
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    func findFileByNormalizedPath(_ normalizedPath: String, rootIDs: Set<String>) throws -> MarkdownFile? {
        guard !rootIDs.isEmpty else { return nil }
        let ids = Array(rootIDs).sorted()
        let placeholders = ids.enumerated().map { "?\($0.offset + 2)" }.joined(separator: ",")
        return try locked {
            try query("""
        SELECT id, path, relative_path, title, size_bytes, modified_at FROM files
        WHERE lower(replace(relative_path, ' ', '')) = ?1 AND root_id IN (\(placeholders))
        LIMIT 1
        """) { statement in
            bindText(statement, 1, normalizedPath)
            for (index, id) in ids.enumerated() { bindText(statement, Int32(index + 2), id) }
        } map: { statement in
            markdownFile(from: statement)
        }.first
        }
    }

    func findFileContainingNormalizedPath(_ normalizedPath: String, rootIDs: Set<String>) throws -> MarkdownFile? {
        guard !rootIDs.isEmpty, normalizedPath.count >= 12 else { return nil }
        let ids = Array(rootIDs).sorted()
        let placeholders = ids.enumerated().map { "?\($0.offset + 2)" }.joined(separator: ",")
        return try locked {
            try query("""
        SELECT id, path, relative_path, title, size_bytes, modified_at FROM files
        WHERE lower(replace(relative_path, ' ', '')) LIKE ?1 AND root_id IN (\(placeholders))
        ORDER BY length(relative_path) ASC, relative_path ASC
        LIMIT 1
        """) { statement in
            bindText(statement, 1, "%\(normalizedPath)%")
            for (index, id) in ids.enumerated() { bindText(statement, Int32(index + 2), id) }
        } map: { statement in
            markdownFile(from: statement)
        }.first
        }
    }

    func children(parentPath: String?, limit: Int) throws -> LibraryChildren {
        let rootIDs = Set(try roots().map(\.id))
        return try children(parentPath: parentPath, rootIDs: rootIDs, limit: limit)
    }

    func children(parentPath: String?, rootIDs: Set<String>, limit: Int) throws -> LibraryChildren {
        let normalizedParent = parentPath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return .empty }
        guard !rootIDs.isEmpty else { return .empty }

        return try locked {
            let folders = try directFolders(parentPath: normalizedParent, rootIDs: rootIDs, limit: safeLimit)
            let remainingFileLimit = max(0, safeLimit - folders.count)
            let files = try directFiles(parentPath: normalizedParent, rootIDs: rootIDs, limit: remainingFileLimit)
            return LibraryChildren(folders: folders, files: files)
        }
    }

    private func rootFilter(_ rootIDs: Set<String>, firstIndex: Int32 = 0) -> (String, [String]) {
        let ids = Array(rootIDs).sorted()
        let values = ids.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }.joined(separator: ",")
        return ("root_id IN (\(values))", ids)
    }

    private func directFolders(parentPath: String, rootIDs: Set<String>, limit: Int) throws -> [LibraryFolder] {
        let rootClause = rootFilter(rootIDs)
        if parentPath.isEmpty {
            return try query("""
        SELECT DISTINCT substr(relative_path, 1, instr(relative_path, '/') - 1) AS folder_name
        FROM files
        WHERE instr(relative_path, '/') > 0 AND \(rootClause.0)
        ORDER BY folder_name ASC
        LIMIT ?1
        """) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
        } map: { statement in
            let name = columnText(statement, 0)
            return LibraryFolder(id: name, path: name, name: name)
        }
        }

        let prefix = parentPath + "/"
        return try query("""
        SELECT DISTINCT substr(substr(relative_path, ?1 + 1), 1, instr(substr(relative_path, ?1 + 1), '/') - 1) AS folder_name
        FROM files
        WHERE relative_path LIKE ?2 AND instr(substr(relative_path, ?1 + 1), '/') > 0 AND \(rootClause.0)
        ORDER BY folder_name ASC
        LIMIT ?3
        """) { statement in
            sqlite3_bind_int(statement, 1, Int32(prefix.count))
            bindText(statement, 2, escapedLikePrefix(prefix) + "%")
            sqlite3_bind_int(statement, 3, Int32(limit))
        } map: { statement in
            let name = columnText(statement, 0)
            let path = prefix + name
            return LibraryFolder(id: path, path: path, name: name)
        }
    }

    private func directFiles(parentPath: String, rootIDs: Set<String>, limit: Int) throws -> [MarkdownFile] {
        guard limit > 0 else { return [] }
        let rootClause = rootFilter(rootIDs)

        if parentPath.isEmpty {
            return try query("""
        SELECT id, path, relative_path, title, size_bytes, modified_at FROM files
        WHERE instr(relative_path, '/') = 0 AND \(rootClause.0)
        ORDER BY relative_path ASC
        LIMIT ?1
        """) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
        } map: { statement in
            markdownFile(from: statement)
        }
        }

        let prefix = parentPath + "/"
        return try query("""
        SELECT id, path, relative_path, title, size_bytes, modified_at FROM files
        WHERE relative_path LIKE ?1 AND instr(substr(relative_path, ?2 + 1), '/') = 0 AND \(rootClause.0)
        ORDER BY relative_path ASC
        LIMIT ?3
        """) { statement in
            bindText(statement, 1, escapedLikePrefix(prefix) + "%")
            sqlite3_bind_int(statement, 2, Int32(prefix.count))
            sqlite3_bind_int(statement, 3, Int32(limit))
        } map: { statement in
            markdownFile(from: statement)
        }
    }

    func fileByID(_ id: String) throws -> MarkdownFile? {
        try locked {
            try query("SELECT id, path, relative_path, title, size_bytes, modified_at FROM files WHERE id = ?1 LIMIT 1", bind: { statement in
                bindText(statement, 1, id)
            }, map: { statement in
                markdownFile(from: statement)
            }).first
        }
    }

    func filesByIDs(_ ids: Set<String>) throws -> [MarkdownFile] {
        try locked {
            var files: [MarkdownFile] = []
            for id in ids.sorted() {
                if let file = try query("SELECT id, path, relative_path, title, size_bytes, modified_at FROM files WHERE id = ?1 LIMIT 1", bind: { statement in
                    bindText(statement, 1, id)
                }, map: { statement in
                    markdownFile(from: statement)
                }).first {
                    files.append(file)
                }
            }
            return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }
    }

    func countFiles() throws -> Int {
        try locked {
            try query("SELECT COUNT(*) FROM files") { statement in
                Int(sqlite3_column_int(statement, 0))
            }.first ?? 0
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func exec(_ sql: String) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil))
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func query<T>(_ sql: String, map: (OpaquePointer?) throws -> T) throws -> [T] {
        try query(sql, bind: { _ in }, map: map)
    }

    private func query<T>(_ sql: String, bind: (OpaquePointer?) throws -> Void, map: (OpaquePointer?) throws -> T) throws -> [T] {
        try withStatement(sql) { statement in
            try bind(statement)
            var rows: [T] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(try map(statement))
            }
            return rows
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        try check(sqlite3_step(statement) == SQLITE_DONE ? SQLITE_OK : sqlite3_errcode(db))
    }

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite error \(code)"
            throw LibraryStoreError.sqlite(message)
        }
    }
}

enum LibraryStoreError: LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        }
    }
}

private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
    guard let text = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: text)
}

private func markdownFile(from statement: OpaquePointer?) -> MarkdownFile {
    let path = columnText(statement, 1)
    return MarkdownFile(
        id: columnText(statement, 0),
        url: URL(fileURLWithPath: path),
        relativePath: columnText(statement, 2),
        title: columnText(statement, 3),
        sizeBytes: sqlite3_column_int64(statement, 4),
        modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
    )
}

private func escapedLikePrefix(_ value: String) -> String {
    value
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

import XCTest
#if GRDBCIPHER
    import GRDBCipher
#elseif GRDBCUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

private struct T1: Codable, RowConvertible, TableMapping {
    static let databaseTableName = "t1"
    var id: Int64
    var name: String
}

private struct T2: Codable, RowConvertible, TableMapping {
    static let databaseTableName = "t2"
    var id: Int64
    var t1id: Int64
    var name: String
}

private struct T3: Codable, RowConvertible, TableMapping {
    static let databaseTableName = "t3"
    static let databaseSelection: [SQLSelectable] = [Column("t1id"), Column("name")]
    var t1id: Int64
    var name: String
}

private struct T4: Codable, RowConvertible, TableMapping {
    static let databaseTableName = "t4"
    var t1id: Int64
    var name: String
}

private struct T5: Codable, RowConvertible, TableMapping {
    static let databaseTableName = "t5"
    var id: Int64
    var t3id: Int64?
    var t4id: Int64?
    var name: String
}

private struct FlatModel: RowConvertible {
    var t1: T1
    var t2Left: T2?
    var t2Right: T2?
    var t3: T3?
    var t5count: Int
    
    init(row: Row) {
        self.t1 = T1(row: row.scoped(on: "t1")!)
        self.t2Left = T2(leftJoinedRow: row.scoped(on: "t2Left"))
        self.t2Right = T2(leftJoinedRow: row.scoped(on: "t2Right"))
        self.t3 = T3(leftJoinedRow: row.scoped(on: "t3"))
        self.t5count = row.scoped(on: "suffix")!["t5count"]
    }
}

private struct CodableFlatModel: RowConvertible, Codable {
    var t1: T1
    var t2Left: T2?
    var t2Right: T2?
    var t3: T3?
    var t5count: Int
}

private struct CodableNestedModel: RowConvertible, Codable {
    struct T2Pair: Codable {
        var left: T2?
        var right: T2?
    }
    var t1: T1
    var optionalT2Pair: T2Pair?
    var t2Pair: T2Pair
    var t3: T3?
    var t5count: Int
}

class JoinSupportTests: GRDBTestCase {
    
    let expectedSQL = """
        SELECT
            "t1".*,
            "t2Left".*,
            "t2Right".*,
            "t3"."t1id", "t3"."name",
            COUNT(DISTINCT t5.id) AS t5count
        FROM t1
        LEFT JOIN t2 t2Left ON t2Left.t1id = t1.id AND t2Left.name = 'left'
        LEFT JOIN t2 t2Right ON t2Right.t1id = t1.id AND t2Right.name = 'right'
        LEFT JOIN t3 ON t3.t1id = t1.id
        LEFT JOIN t4 ON t4.t1id = t1.id
        LEFT JOIN t5 ON t5.t3id = t3.t1id OR t5.t4id = t4.t1id
        GROUP BY t1.id
        ORDER BY t1.id
        """
    
    let testedSQL = """
        SELECT
            \(T1.selectionSQL()),
            \(T2.selectionSQL(alias: "t2Left")),
            \(T2.selectionSQL(alias: "t2Right")),
            \(T3.selectionSQL()),
            COUNT(DISTINCT t5.id) AS t5count
        FROM t1
        LEFT JOIN t2 t2Left ON t2Left.t1id = t1.id AND t2Left.name = 'left'
        LEFT JOIN t2 t2Right ON t2Right.t1id = t1.id AND t2Right.name = 'right'
        LEFT JOIN t3 ON t3.t1id = t1.id
        LEFT JOIN t4 ON t4.t1id = t1.id
        LEFT JOIN t5 ON t5.t3id = t3.t1id OR t5.t4id = t4.t1id
        GROUP BY t1.id
        ORDER BY t1.id
        """
    
    override func setup(_ dbWriter: DatabaseWriter) throws {
        try dbWriter.write { db in
            try db.create(table: "t1") { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text).notNull()
            }
            try db.create(table: "t2") { t in
                t.column("id", .integer).primaryKey()
                t.column("t1id", .integer).notNull().references("t1", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.uniqueKey(["t1id", "name"])
            }
            try db.create(table: "t3") { t in
                t.column("t1id", .integer).primaryKey().references("t1", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("ignored", .integer)
            }
            try db.create(table: "t4") { t in
                t.column("t1id", .integer).primaryKey().references("t1", onDelete: .cascade)
                t.column("name", .text).notNull()
            }
            try db.create(table: "t5") { t in
                t.column("id", .integer).primaryKey()
                t.column("t3id", .integer).references("t3", onDelete: .cascade)
                t.column("t4id", .integer).references("t4", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.check(sql: "(t3id IS NOT NULL) + (t4id IS NOT NULL) = 1")
            }
            
            // Sample data
            
            try db.execute("""
                INSERT INTO t1 (id, name) VALUES (1, 'A1');
                INSERT INTO t1 (id, name) VALUES (2, 'A2');
                INSERT INTO t1 (id, name) VALUES (3, 'A3');
                INSERT INTO t2 (id, t1id, name) VALUES (1, 1, 'left');
                INSERT INTO t2 (id, t1id, name) VALUES (2, 1, 'right');
                INSERT INTO t2 (id, t1id, name) VALUES (3, 2, 'left');
                INSERT INTO t3 (t1id, name) VALUES (1, 'A3');
                INSERT INTO t4 (t1id, name) VALUES (1, 'A4');
                INSERT INTO t4 (t1id, name) VALUES (2, 'B4');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (1, 1, NULL, 'A5');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (2, 1, NULL, 'B5');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (3, NULL, 1, 'C5');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (4, NULL, 1, 'D5');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (5, NULL, 1, 'E5');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (6, NULL, 2, 'F5');
                INSERT INTO t5 (id, t3id, t4id, name) VALUES (7, NULL, 2, 'G5');
                """)
        }
    }
    
    func testSampleData() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let rows = try Row.fetchAll(db, expectedSQL)
            XCTAssertEqual(rows.count, 3)
            XCTAssertEqual(rows[0], [
                // t1.*
                "id": 1, "name": "A1",
                // t2Left.*
                "id": 1, "t1id": 1, "name": "left",
                // t2Right.*
                "id": 2, "t1id": 1, "name": "right",
                // t3.*
                "t1id": 1, "name": "A3",
                // t5count
                "t5count": 5])
            XCTAssertEqual(rows[1], [
                // t1.*
                "id": 2, "name": "A2",
                // t2Left.*
                "id": 3, "t1id": 2, "name": "left",
                // t2Right.*
                "id": nil, "t1id": nil, "name": nil,
                // t3.*
                "t1id": nil, "name": nil,
                // t5count
                "t5count": 2])
            XCTAssertEqual(rows[2], [
                // t1.*
                "id": 3, "name": "A3",
                // t2Left.*
                "id": nil, "t1id": nil, "name": nil,
                // t2Right.*
                "id": nil, "t1id": nil, "name": nil,
                // t3.*
                "t1id": nil, "name": nil,
                // t5count
                "t5count": 0])
        }
    }
    
    func testTestedSQL() throws {
        XCTAssertEqual(testedSQL, expectedSQL)
    }
    
    func testSplittingRowAdapters() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let request = SQLRequest(testedSQL).adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    T1.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T3.numberOfSelectedColumns(db)])
                return ScopeAdapter([
                    "t1": adapters[0],
                    "t2Left": adapters[1],
                    "t2Right": adapters[2],
                    "t3": adapters[3],
                    "suffix": adapters[4]])
            }
            let rows = try Row.fetchAll(db, request)
            XCTAssertEqual(rows.count, 3)
            
            XCTAssertEqual(rows[0].unscoped, [
                // t1.*
                "id": 1, "name": "A1",
                // t2Left.*
                "id": 1, "t1id": 1, "name": "left",
                // t2Right.*
                "id": 2, "t1id": 1, "name": "right",
                // t3.*
                "t1id": 1, "name": "A3",
                // t5count
                "t5count": 5])
            XCTAssertEqual(rows[0].scoped(on: "t1")!, ["id": 1, "name": "A1"])
            XCTAssertEqual(rows[0].scoped(on: "t2Left")!, ["id": 1, "t1id": 1, "name": "left"])
            XCTAssertEqual(rows[0].scoped(on: "t2Right")!, ["id": 2, "t1id": 1, "name": "right"])
            XCTAssertEqual(rows[0].scoped(on: "t3")!, ["t1id": 1, "name": "A3"])
            XCTAssertEqual(rows[0].scoped(on: "suffix")!, ["t5count": 5])
            
            XCTAssertEqual(rows[1].unscoped, [
                // t1.*
                "id": 2, "name": "A2",
                // t2Left.*
                "id": 3, "t1id": 2, "name": "left",
                // t2Right.*
                "id": nil, "t1id": nil, "name": nil,
                // t3.*
                "t1id": nil, "name": nil,
                // t5count
                "t5count": 2])
            XCTAssertEqual(rows[1].scoped(on: "t1")!, ["id": 2, "name": "A2"])
            XCTAssertEqual(rows[1].scoped(on: "t2Left")!, ["id": 3, "t1id": 2, "name": "left"])
            XCTAssertEqual(rows[1].scoped(on: "t2Right")!, ["id": nil, "t1id": nil, "name": nil])
            XCTAssertEqual(rows[1].scoped(on: "t3")!, ["t1id": nil, "name": nil])
            XCTAssertEqual(rows[1].scoped(on: "suffix")!, ["t5count": 2])
            
            XCTAssertEqual(rows[2].unscoped, [
                // t1.*
                "id": 3, "name": "A3",
                // t2Left.*
                "id": nil, "t1id": nil, "name": nil,
                // t2Right.*
                "id": nil, "t1id": nil, "name": nil,
                // t3.*
                "t1id": nil, "name": nil,
                // t5count
                "t5count": 0])
            XCTAssertEqual(rows[2].scoped(on: "t1")!, ["id": 3, "name": "A3"])
            XCTAssertEqual(rows[2].scoped(on: "t2Left")!, ["id": nil, "t1id": nil, "name": nil])
            XCTAssertEqual(rows[2].scoped(on: "t2Right")!, ["id": nil, "t1id": nil, "name": nil])
            XCTAssertEqual(rows[2].scoped(on: "t3")!, ["t1id": nil, "name": nil])
            XCTAssertEqual(rows[2].scoped(on: "suffix")!, ["t5count": 0])
        }
    }
    
    func testFlatModel() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let request = SQLRequest(testedSQL).adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    T1.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T3.numberOfSelectedColumns(db)])
                return ScopeAdapter([
                    "t1": adapters[0],
                    "t2Left": adapters[1],
                    "t2Right": adapters[2],
                    "t3": adapters[3],
                    "suffix": adapters[4]])
            }
            let models = try FlatModel.fetchAll(db, request)
            XCTAssertEqual(models.count, 3)
            
            XCTAssertEqual(models[0].t1.id, 1)
            XCTAssertEqual(models[0].t1.name, "A1")
            XCTAssertEqual(models[0].t2Left!.id, 1)
            XCTAssertEqual(models[0].t2Left!.t1id, 1)
            XCTAssertEqual(models[0].t2Left!.name, "left")
            XCTAssertEqual(models[0].t2Right!.id, 2)
            XCTAssertEqual(models[0].t2Right!.t1id, 1)
            XCTAssertEqual(models[0].t2Right!.name, "right")
            XCTAssertEqual(models[0].t3!.t1id, 1)
            XCTAssertEqual(models[0].t3!.name, "A3")
            XCTAssertEqual(models[0].t5count, 5)
            
            XCTAssertEqual(models[1].t1.id, 2)
            XCTAssertEqual(models[1].t1.name, "A2")
            XCTAssertEqual(models[1].t2Left!.id, 3)
            XCTAssertEqual(models[1].t2Left!.t1id, 2)
            XCTAssertEqual(models[1].t2Left!.name, "left")
            XCTAssertNil(models[1].t2Right)
            XCTAssertNil(models[1].t3)
            XCTAssertEqual(models[1].t5count, 2)
            
            XCTAssertEqual(models[2].t1.id, 3)
            XCTAssertEqual(models[2].t1.name, "A3")
            XCTAssertNil(models[2].t2Left)
            XCTAssertNil(models[2].t2Right)
            XCTAssertNil(models[2].t3)
            XCTAssertEqual(models[2].t5count, 0)
        }
    }
    
    func testCodableFlatModel() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let request = SQLRequest(testedSQL).adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    T1.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T3.numberOfSelectedColumns(db)])
                return ScopeAdapter([
                    "t1": adapters[0],
                    "t2Left": adapters[1],
                    "t2Right": adapters[2],
                    "t3": adapters[3]])
            }
            let models = try CodableFlatModel.fetchAll(db, request)
            XCTAssertEqual(models.count, 3)
            
            XCTAssertEqual(models[0].t1.id, 1)
            XCTAssertEqual(models[0].t1.name, "A1")
            XCTAssertEqual(models[0].t2Left!.id, 1)
            XCTAssertEqual(models[0].t2Left!.t1id, 1)
            XCTAssertEqual(models[0].t2Left!.name, "left")
            XCTAssertEqual(models[0].t2Right!.id, 2)
            XCTAssertEqual(models[0].t2Right!.t1id, 1)
            XCTAssertEqual(models[0].t2Right!.name, "right")
            XCTAssertEqual(models[0].t3!.t1id, 1)
            XCTAssertEqual(models[0].t3!.name, "A3")
            XCTAssertEqual(models[0].t5count, 5)
            
            XCTAssertEqual(models[1].t1.id, 2)
            XCTAssertEqual(models[1].t1.name, "A2")
            XCTAssertEqual(models[1].t2Left!.id, 3)
            XCTAssertEqual(models[1].t2Left!.t1id, 2)
            XCTAssertEqual(models[1].t2Left!.name, "left")
            XCTAssertNil(models[1].t2Right)
            XCTAssertNil(models[1].t3)
            XCTAssertEqual(models[1].t5count, 2)
            
            XCTAssertEqual(models[2].t1.id, 3)
            XCTAssertEqual(models[2].t1.name, "A3")
            XCTAssertNil(models[2].t2Left)
            XCTAssertNil(models[2].t2Right)
            XCTAssertNil(models[2].t3)
            XCTAssertEqual(models[2].t5count, 0)
        }
    }
    
    func testCodableNestedModel() throws {
        let dbQueue = try makeDatabaseQueue()
        try dbQueue.inDatabase { db in
            let request = SQLRequest(testedSQL).adapted { db in
                let adapters = try splittingRowAdapters(columnCounts: [
                    T1.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T2.numberOfSelectedColumns(db),
                    T3.numberOfSelectedColumns(db)])
                return ScopeAdapter([
                    "t1": adapters[0],
                    "optionalT2Pair": ScopeAdapter(nestedScopes: [
                        "left": adapters[1],
                        "right": adapters[2]]),
                    "t2Pair": ScopeAdapter(nestedScopes: [
                        "left": adapters[1],
                        "right": adapters[2]]),
                    "t3": adapters[3]])
            }
            let models = try CodableNestedModel.fetchAll(db, request)
            XCTAssertEqual(models.count, 3)
            
            XCTAssertEqual(models[0].t1.id, 1)
            XCTAssertEqual(models[0].t1.name, "A1")
            XCTAssertEqual(models[0].optionalT2Pair!.left!.id, 1)
            XCTAssertEqual(models[0].optionalT2Pair!.left!.t1id, 1)
            XCTAssertEqual(models[0].optionalT2Pair!.left!.name, "left")
            XCTAssertEqual(models[0].optionalT2Pair!.right!.id, 2)
            XCTAssertEqual(models[0].optionalT2Pair!.right!.t1id, 1)
            XCTAssertEqual(models[0].optionalT2Pair!.right!.name, "right")
            XCTAssertEqual(models[0].t2Pair.left!.id, 1)
            XCTAssertEqual(models[0].t2Pair.left!.t1id, 1)
            XCTAssertEqual(models[0].t2Pair.left!.name, "left")
            XCTAssertEqual(models[0].t2Pair.right!.id, 2)
            XCTAssertEqual(models[0].t2Pair.right!.t1id, 1)
            XCTAssertEqual(models[0].t2Pair.right!.name, "right")
            XCTAssertEqual(models[0].t3!.t1id, 1)
            XCTAssertEqual(models[0].t3!.name, "A3")
            XCTAssertEqual(models[0].t5count, 5)
            
            XCTAssertEqual(models[1].t1.id, 2)
            XCTAssertEqual(models[1].t1.name, "A2")
            XCTAssertEqual(models[1].optionalT2Pair!.left!.id, 3)
            XCTAssertEqual(models[1].optionalT2Pair!.left!.t1id, 2)
            XCTAssertEqual(models[1].optionalT2Pair!.left!.name, "left")
            XCTAssertEqual(models[1].t2Pair.left!.id, 3)
            XCTAssertEqual(models[1].t2Pair.left!.t1id, 2)
            XCTAssertEqual(models[1].t2Pair.left!.name, "left")
            XCTAssertNil(models[1].optionalT2Pair!.right)
            XCTAssertNil(models[1].t2Pair.right)
            XCTAssertNil(models[1].t3)
            XCTAssertEqual(models[1].t5count, 2)
            
            XCTAssertEqual(models[2].t1.id, 3)
            XCTAssertEqual(models[2].t1.name, "A3")
            XCTAssertNil(models[2].optionalT2Pair)
            XCTAssertNil(models[2].t2Pair.left)
            XCTAssertNil(models[2].t2Pair.right)
            XCTAssertNil(models[2].t3)
            XCTAssertEqual(models[2].t5count, 0)
        }
    }
}
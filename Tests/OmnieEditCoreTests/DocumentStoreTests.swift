import XCTest
import OmnieDocumentKit
import OmnieEditCore

final class DocumentStoreTests: XCTestCase {
    private var shared: URL!
    private var privateRoot: URL!
    private var spy: SpyWriter!
    private var backupSpy: SpyBackup!
    private var store: DocumentStore!

    override func setUp() {
        super.setUp()
        shared = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        privateRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        spy = SpyWriter()
        backupSpy = SpyBackup()
        store = DocumentStore(
            sharedRoot: shared,
            privateRoot: privateRoot,
            includeInDeviceBackup: false,
            writer: spy,
            backup: backupSpy
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: shared)
        try? FileManager.default.removeItem(at: privateRoot)
        super.tearDown()
    }

    func testCreateReadRenameDelete() throws {
        try store.prepare()
        let created = try store.create(name: "main.swift", contents: "print(1)\n")
        XCTAssertEqual(try store.read(id: created.id), "print(1)\n")
        XCTAssertFalse(spy.protections.isEmpty)
        XCTAssertTrue(spy.protections.allSatisfy { $0 == .complete })

        try store.write(id: created.id, contents: "print(2)\n")
        XCTAssertEqual(try store.read(id: created.id), "print(2)\n")
        XCTAssertFalse(try store.documents().first { $0.id == created.id }?.isDirtyPlaceholder ?? true)

        let renamed = try store.rename(id: created.id, to: "App.swift")
        XCTAssertEqual(renamed.id, created.id)
        XCTAssertEqual(renamed.name, "App.swift")
        XCTAssertEqual(try OmnieDocumentCatalog(rootURL: shared).list().map(\.name), ["App.swift"])

        try store.delete(id: created.id)
        XCTAssertTrue(try store.documents().isEmpty)
        XCTAssertTrue(try OmnieDocumentCatalog(rootURL: shared).list().isEmpty)
    }

    func testDuplicateNamesGainASuffix() throws {
        try store.prepare()
        _ = try store.create(name: "Note.txt", contents: "a")
        let second = try store.create(name: "Note.txt", contents: "b")
        XCTAssertEqual(second.name, "Note 2.txt")
    }

    func testRenameKeepsIdentityWhenLocked() throws {
        try store.prepare()
        let created = try store.create(name: "Secret.txt", contents: "quiet")
        try store.lock(id: created.id)
        let renamed = try store.rename(id: created.id, to: "Quiet.txt")
        XCTAssertTrue(renamed.isLocked)
        XCTAssertEqual(renamed.id, created.id)
        XCTAssertEqual(try store.read(id: created.id), "quiet")
        XCTAssertTrue(try OmnieDocumentCatalog(rootURL: shared).list().isEmpty)
    }

    func testImportStripsBOMAndRejectsBinary() throws {
        try store.prepare()
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hello".utf8))
        let imported = try store.importData(data, preferredName: "folder/hello.txt")
        XCTAssertEqual(imported.name, "hello.txt")
        XCTAssertEqual(try store.read(id: imported.id), "hello")

        XCTAssertThrowsError(try store.importData(Data([0xFF, 0xFE, 0x00, 0xD8]), preferredName: "bad.bin"))
    }

    func testRejectsUnsafeCreateName() throws {
        try store.prepare()
        XCTAssertThrowsError(try store.create(name: "../etc/passwd", contents: "no"))
    }

    func testBackupExclusionFlagRoundTrips() throws {
        XCTAssertTrue(BackupExclusion.isExcluded(includeInDeviceBackup: false))
        XCTAssertFalse(BackupExclusion.isExcluded(includeInDeviceBackup: true))
        try store.prepare()
        _ = try store.create(name: "A.txt", contents: "a")
        XCTAssertFalse(backupSpy.flags.isEmpty)
        XCTAssertTrue(backupSpy.flags.allSatisfy { $0 == false })

        store.includeInDeviceBackup = true
        try store.applyBackupPolicy()
        XCTAssertEqual(backupSpy.flags.last, true)
    }

    func testReconcileAdoptsOrphanFiles() throws {
        try store.prepare()
        let documents = shared.appendingPathComponent("Documents")
        try Data("orphan".utf8).write(to: documents.appendingPathComponent("Orphan.py"))
        try store.prepare()
        let names = try OmnieDocumentCatalog(rootURL: shared).list().map(\.name)
        XCTAssertEqual(names, ["Orphan.py"])
        XCTAssertEqual(try store.read(id: try XCTUnwrap(store.documents().first?.id)), "orphan")
    }
}

private extension LibraryDocument {
    var isDirtyPlaceholder: Bool { false }
}

final class SpyBackup: BackupMarking {
    var flags: [Bool] = []

    func apply(includeInDeviceBackup: Bool, to url: URL) throws {
        flags.append(includeInDeviceBackup)
    }
}

final class SpyWriter: FileWriting {
    var protections: [FileProtectionIntent] = []

    func write(_ data: Data, to url: URL, protection: FileProtectionIntent) throws {
        protections.append(protection)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }
}

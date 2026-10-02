import XCTest
import OmnieDocumentKit
import OmnieEditCore

final class CatalogContractTests: XCTestCase {
    func testExampleCatalogDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Contract/catalog.example.json")
        let data = try Data(contentsOf: url)
        let catalog = try OmnieJSON.decoder().decode(OmnieCatalog.self, from: data)
        XCTAssertEqual(catalog.contractVersion, OmnieContract.version)
        XCTAssertEqual(catalog.documents.map(\.id), ["7f2c9c2e-1b4a-4e0a-9c11-6a1d0e5b9a10"])
        XCTAssertEqual(catalog.documents[0].name, "ContentView.swift")
        XCTAssertEqual(catalog.documents[0].fileExtension, "swift")
        XCTAssertEqual(catalog.documents[0].relativePath, "ContentView.swift")
    }

    func testRejectsFutureContractVersion() throws {
        let root = try makeRoot()
        let catalogURL = root.appendingPathComponent("catalog.json")
        let body = """
        {"contractVersion":2,"generatedAt":"2026-10-02T00:00:00Z","documents":[]}
        """
        try body.data(using: .utf8)?.write(to: catalogURL)
        let catalog = OmnieDocumentCatalog(rootURL: root)
        XCTAssertThrowsError(try catalog.list()) { error in
            XCTAssertEqual(
                error as? OmnieDocumentError,
                .unsupportedContractVersion(found: 2, supported: 1)
            )
        }
    }

    func testSkipsUnsafeCatalogEntries() throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Documents"),
            withIntermediateDirectories: true
        )
        let body = """
        {
          "contractVersion": 1,
          "generatedAt": "2026-10-02T00:00:00Z",
          "documents": [
            {
              "id": "bad",
              "name": "../secret",
              "extension": "txt",
              "relativePath": "../secret",
              "byteCount": 1,
              "modifiedAt": "2026-10-02T00:00:00Z"
            }
          ]
        }
        """
        try Data(body.utf8).write(to: root.appendingPathComponent("catalog.json"))
        let listed = try OmnieDocumentCatalog(rootURL: root).list()
        XCTAssertTrue(listed.isEmpty)
        XCTAssertThrowsError(try OmnieDocumentCatalog(rootURL: root).fileURL(relativePath: "../secret"))
    }

    func testPeerReadsWhatTheStoreWritesAndLosesLockedFiles() throws {
        let shared = try makeRoot()
        let privateRoot = try makeRoot()
        let store = DocumentStore(sharedRoot: shared, privateRoot: privateRoot)
        try store.prepare()
        let created = try store.create(name: "App.swift", contents: "let a = 1\n", now: Date(timeIntervalSince1970: 1_700_000_000))
        let peer = OmnieDocumentCatalog(rootURL: shared)
        let listed = try peer.list()
        XCTAssertEqual(listed.map(\.id), [created.id])
        XCTAssertEqual(try peer.read(id: created.id), "let a = 1\n")
        let payload = try Data(contentsOf: peer.catalogFileURL)
        let decoded = try OmnieJSON.decoder().decode(OmnieCatalog.self, from: payload)
        XCTAssertEqual(decoded.contractVersion, 1)
        XCTAssertEqual(decoded.documents[0].relativePath, "App.swift")

        try store.lock(id: created.id)
        XCTAssertTrue(try peer.list().isEmpty)
        XCTAssertThrowsError(try peer.read(id: created.id)) { error in
            XCTAssertEqual(error as? OmnieDocumentError, .documentNotFound(id: created.id))
        }
        XCTAssertEqual(try store.read(id: created.id), "let a = 1\n")

        let unlocked = try store.unlock(id: created.id)
        XCTAssertEqual(unlocked.id, created.id)
        XCTAssertEqual(try peer.read(id: created.id), "let a = 1\n")
    }

    private func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

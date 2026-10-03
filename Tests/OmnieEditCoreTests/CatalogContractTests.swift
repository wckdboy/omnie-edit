import XCTest
import OmnieDocumentKit

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

    private func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

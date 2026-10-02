import XCTest
import OmnieDocumentKit

final class OmnieFileNameTests: XCTestCase {
    func testAcceptsSourceFileName() {
        XCTAssertEqual(try OmnieFileName.validateDisplayName("ContentView.swift").get(), "ContentView.swift")
    }

    func testRejectsTraversalAndSeparators() {
        XCTAssertEqual(OmnieFileName.validateDisplayName("../secret").error, .nameRejected("../secret"))
        XCTAssertEqual(OmnieFileName.validateDisplayName("a/b.swift").error, .nameRejected("a/b.swift"))
        XCTAssertEqual(OmnieFileName.validateRelativePath("..").error, .unsafePath(".."))
        XCTAssertEqual(OmnieFileName.validateDisplayName(".hidden").error, .nameRejected(".hidden"))
        XCTAssertEqual(OmnieFileName.validateDisplayName("trailing.").error, .nameRejected("trailing."))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(try OmnieFileName.validateDisplayName("  main.swift  ").get(), "main.swift")
    }

    func testSplitsExtension() {
        XCTAssertEqual(OmnieFileName.splittingExtension("Archive.tar.gz").base, "Archive.tar")
        XCTAssertEqual(OmnieFileName.splittingExtension("Archive.tar.gz").ext, "gz")
        XCTAssertEqual(OmnieFileName.splittingExtension("Makefile").ext, "")
        XCTAssertEqual(OmnieFileName.splittingExtension(".gitignore").base, ".gitignore")
    }

    func testUniquesBeforeExtension() {
        let name = OmnieFileName.uniqued("App.swift", existing: ["App.swift", "App 2.swift"])
        XCTAssertEqual(name, "App 3.swift")
    }

    func testLastPathComponentDropsDirectories() {
        XCTAssertEqual(OmnieFileName.lastPathComponent(#"../Incoming/View.swift"#), "View.swift")
        XCTAssertEqual(OmnieFileName.lastPathComponent(#"C:\Temp\View.swift"#), "View.swift")
    }
}

private extension Result where Failure == OmnieDocumentError {
    var error: OmnieDocumentError? {
        switch self {
        case .success:
            return nil
        case let .failure(error):
            return error
        }
    }
}

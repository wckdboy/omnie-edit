import XCTest
import OmnieEditCore

final class WorkspaceTests: XCTestCase {
    func testCoordinatedTextFileRoundTripsUTF8AndStripsBOM() throws {
        let root = try makeRoot()
        let file = CoordinatedTextFile()

        let plain = root.appendingPathComponent("plain.txt")
        try file.write("hello\nworld", to: plain)
        XCTAssertEqual(try file.read(from: plain), "hello\nworld")

        let withBOM = root.appendingPathComponent("bom.txt")
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(Data("bonjour".utf8))
        try bytes.write(to: withBOM)
        XCTAssertEqual(try file.read(from: withBOM), "bonjour")
    }

    func testTextFileRejectsBinaryAndOversizedInput() throws {
        let root = try makeRoot()
        let file = CoordinatedTextFile()

        let binary = root.appendingPathComponent("binary.dat")
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: binary)
        XCTAssertThrowsError(try file.read(from: binary)) { error in
            XCTAssertEqual(error as? WorkspaceError, .notUTF8(name: "binary.dat"))
        }

        let small = CoordinatedTextFile(maximumBytes: 8)
        XCTAssertThrowsError(try small.write("way too long for the limit", to: root.appendingPathComponent("huge.txt"))) { error in
            XCTAssertEqual(
                error as? WorkspaceError,
                .fileTooLarge(name: "huge.txt", maximumBytes: 8)
            )
        }

        let oversizedOnDisk = root.appendingPathComponent("grew.txt")
        try Data("way too long for the limit".utf8).write(to: oversizedOnDisk)
        XCTAssertThrowsError(try small.read(from: oversizedOnDisk))
    }

    func testProjectFileSystemCreatesRenamesDuplicatesAndDeletes() throws {
        let root = try makeRoot()
        let projectFileSystem = ProjectFileSystem()

        let created = try projectFileSystem.createFile(named: "note.txt", in: root, projectRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))

        XCTAssertThrowsError(try projectFileSystem.createFile(named: "note.txt", in: root, projectRoot: root)) { error in
            XCTAssertEqual(error as? WorkspaceError, .fileAlreadyExists(name: "note.txt"))
        }
        XCTAssertThrowsError(try projectFileSystem.createFile(named: "a/b", in: root, projectRoot: root)) { error in
            XCTAssertEqual(error as? WorkspaceError, .invalidName)
        }

        let renamed = try projectFileSystem.rename(created, to: "renamed.txt", projectRoot: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))

        let duplicated = try projectFileSystem.duplicate(renamed, projectRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicated.path))
        XCTAssertEqual(duplicated.lastPathComponent, "renamed copy.txt")

        try projectFileSystem.delete(duplicated, projectRoot: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicated.path))
    }

    func testProjectItemsMoveBetweenFoldersWithoutAllowingRecursiveMoves() throws {
        let root = try makeRoot()
        let projectFileSystem = ProjectFileSystem()

        let subfolder = try projectFileSystem.createFolder(named: "Sub", in: root, projectRoot: root)
        let file = try projectFileSystem.createFile(named: "note.txt", in: root, projectRoot: root)

        let moved = try projectFileSystem.move(file, to: subfolder, projectRoot: root)
        XCTAssertEqual(moved, subfolder.appendingPathComponent("note.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))

        XCTAssertThrowsError(try projectFileSystem.move(subfolder, to: subfolder, projectRoot: root)) { error in
            guard case .invalidMove = error as? WorkspaceError else {
                return XCTFail("Expected invalidMove, got \(error)")
            }
        }

        let outside = try makeRoot()
        XCTAssertThrowsError(try projectFileSystem.move(moved, to: outside, projectRoot: root)) { error in
            guard case .invalidMove = error as? WorkspaceError else {
                return XCTFail("Expected invalidMove, got \(error)")
            }
        }
    }

    func testProjectBrowserHonorsGitIgnoreButShowsOtherDotfiles() throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("build"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("visible.txt"))
        try Data().write(to: root.appendingPathComponent(".env"))

        let entries = try ProjectFileSystem().children(of: root, projectRoot: root)
        let names = Set(entries.map(\.name))
        XCTAssertTrue(names.contains("visible.txt"))
        XCTAssertTrue(names.contains(".env"))
        XCTAssertFalse(names.contains("build"))
        XCTAssertFalse(names.contains(".git"))
    }

    func testProjectSearchFindsNestedFilesAndHonorsIgnores() throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ignored/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let nested = root.appendingPathComponent("deep/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("target-match.txt"))

        let ignored = root.appendingPathComponent("ignored", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try Data().write(to: ignored.appendingPathComponent("target-match.txt"))

        let results = try ProjectFileSystem().search(for: "target-match", projectRoot: root)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "deep/nested/target-match.txt")
    }

    func testRecentWorkspaceStoreSortsAndCapsItems() throws {
        let suite = "omnie.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = RecentWorkspaceStore(defaults: defaults, limit: 2)

        let oldest = RecentWorkspace(kind: .file, displayName: "oldest", bookmark: Data(), lastOpenedAt: Date(timeIntervalSince1970: 100))
        let middle = RecentWorkspace(kind: .file, displayName: "middle", bookmark: Data(), lastOpenedAt: Date(timeIntervalSince1970: 200))
        let newest = RecentWorkspace(kind: .project, displayName: "newest", bookmark: Data(), lastOpenedAt: Date(timeIntervalSince1970: 300))

        store.save([oldest, middle, newest])
        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.displayName), ["newest", "middle"])
    }

    func testLocalGitStatusStageCommitDiffAndDiscard() throws {
        let root = try makeRoot()
        let git = GitRepositoryService()
        let identity = GitIdentity(name: "Test", email: "test@example.com")

        try git.createRepository(at: root)
        XCTAssertTrue(git.isRepository(at: root))

        let file = root.appendingPathComponent("file.txt")
        try Data("line one\n".utf8).write(to: file)

        let untracked = try git.status(at: root)
        XCTAssertEqual(untracked.map(\.path), ["file.txt"])
        XCTAssertTrue(untracked[0].states.contains(.untracked))

        try git.stage(path: "file.txt", at: root)
        let staged = try git.status(at: root)
        XCTAssertTrue(staged[0].isStaged)

        try git.commit(message: "Initial commit", identity: identity, at: root)
        XCTAssertTrue(try git.status(at: root).isEmpty)

        XCTAssertThrowsError(try git.commit(message: "", identity: identity, at: root)) { error in
            XCTAssertEqual(error as? GitServiceError, .emptyCommitMessage)
        }

        try Data("line one\nline two\n".utf8).write(to: file)
        let changed = try git.status(at: root)
        XCTAssertTrue(changed[0].states.contains(.changed))

        let diff = try git.diff(for: "file.txt", at: root)
        XCTAssertTrue(diff.lines.contains { $0.kind == .addition && $0.text.contains("line two") })

        try git.discard(path: "file.txt", at: root)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "line one\n")
        XCTAssertTrue(try git.status(at: root).isEmpty)

        let untrackedFile = root.appendingPathComponent("scratch.txt")
        try Data("temp".utf8).write(to: untrackedFile)
        try git.discard(path: "scratch.txt", at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedFile.path))
    }

    private func makeRoot() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

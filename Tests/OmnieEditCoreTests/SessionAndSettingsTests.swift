import XCTest
import OmnieEditCore

final class SessionAndSettingsTests: XCTestCase {
    func testSettingsRoundTripAndFallback() throws {
        let suite = "omnie.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(EditorSettingsStore.load(from: defaults), .default)

        var settings = EditorSettings.default
        settings.theme = .monochrome
        settings.fontSize = 99
        settings.defaultExtension = "SWIFT"
        settings.preferredHand = .left
        EditorSettingsStore.save(settings, to: defaults)
        let loaded = EditorSettingsStore.load(from: defaults)
        XCTAssertEqual(loaded.theme, .monochrome)
        XCTAssertEqual(loaded.fontSize, EditorSettings.maxFontSize)
        XCTAssertEqual(loaded.defaultExtension, "swift")
        XCTAssertEqual(loaded.preferredHand, .left)

        defaults.set(Data("[]".utf8), forKey: EditorSettingsStore.storageKey)
        XCTAssertEqual(EditorSettingsStore.load(from: defaults), .default)

        let unknown = """
        {"theme":"neon","fontSize":8,"defaultExtension":"../x"}
        """
        defaults.set(Data(unknown.utf8), forKey: EditorSettingsStore.storageKey)
        let recovered = EditorSettingsStore.load(from: defaults)
        XCTAssertEqual(recovered.theme, .system)
        XCTAssertEqual(recovered.fontSize, EditorSettings.minFontSize)
        XCTAssertEqual(recovered.defaultExtension, "txt")
        XCTAssertEqual(recovered.preferredHand, .right)
    }

    func testEditorSessionAndAutosaveClock() {
        var session = EditorSession(text: "let a = 1")
        XCTAssertFalse(session.isDirty)
        session.draft = "let a = 2"
        XCTAssertTrue(session.isDirty)
        session.noteSaved(snapshot: "let a = 2")
        XCTAssertFalse(session.isDirty)
        session.draft = "let a = 3"
        XCTAssertTrue(session.isDirty)

        var clock = AutosaveClock(delay: 0.7)
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(clock.isDue(at: start))
        clock.markEdited(at: start)
        XCTAssertFalse(clock.isDue(at: start.addingTimeInterval(0.69)))
        XCTAssertTrue(clock.isDue(at: start.addingTimeInterval(0.7)))
        clock.cancel()
        XCTAssertFalse(clock.isDue(at: start.addingTimeInterval(5)))
    }
}

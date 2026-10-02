import XCTest
import OmnieEditCore

final class SessionAndSettingsTests: XCTestCase {
    func testColdStartLocksOnlyWhenEnabled() {
        let open = SessionGate.coldStart(appLockEnabled: false)
        XCTAssertFalse(open.needsAppUnlock)
        XCTAssertFalse(open.privacyCover)

        let locked = SessionGate.coldStart(appLockEnabled: true)
        XCTAssertTrue(locked.needsAppUnlock)
        XCTAssertTrue(locked.privacyCover)
    }

    func testInactiveCoversWithoutDroppingUnlock() {
        let start = SessionGate.coldStart(appLockEnabled: true).grantingAppUnlock()
        let covered = start.transition(.inactive)
        XCTAssertTrue(covered.privacyCover)
        XCTAssertFalse(covered.needsAppUnlock)
        let back = covered.transition(.active)
        XCTAssertFalse(back.privacyCover)
        XCTAssertFalse(back.needsAppUnlock)
    }

    func testBackgroundRelocksAppAndDocuments() {
        var gate = SessionGate.coldStart(appLockEnabled: true).grantingAppUnlock()
        gate = gate.grantingDocumentUnlock(id: "doc")
        let background = gate.transition(.background)
        XCTAssertTrue(background.needsAppUnlock)
        XCTAssertTrue(background.unlockedDocumentIDs.isEmpty)
        XCTAssertTrue(background.needsDocumentUnlock(id: "doc", isLocked: true))
    }

    func testInactiveCanShieldLockedDocumentsWithoutAppLock() {
        let start = SessionGate.coldStart(appLockEnabled: false)
        let covered = start.transition(.inactive, shieldOnInactive: true)
        XCTAssertTrue(covered.privacyCover)
        XCTAssertFalse(covered.needsAppUnlock)
        XCTAssertFalse(covered.transition(.active, shieldOnInactive: true).privacyCover)
    }

    func testBackgroundClearsDocumentUnlocksWhenAppLockIsOff() {
        var gate = SessionGate.coldStart(appLockEnabled: false)
        gate = gate.grantingDocumentUnlock(id: "doc")
        let background = gate.transition(.background)
        XCTAssertFalse(background.needsAppUnlock)
        XCTAssertFalse(background.privacyCover)
        XCTAssertTrue(background.needsDocumentUnlock(id: "doc", isLocked: true))
        XCTAssertFalse(background.needsDocumentUnlock(id: "doc", isLocked: false))
    }

    func testSettingsRoundTripAndFallback() throws {
        let suite = "omnie.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        XCTAssertEqual(EditorSettingsStore.load(from: defaults), .default)

        var settings = EditorSettings.default
        settings.theme = .monochrome
        settings.fontSize = 99
        settings.defaultExtension = "SWIFT"
        settings.appLockEnabled = true
        settings.includeInDeviceBackup = true
        EditorSettingsStore.save(settings, to: defaults)
        let loaded = EditorSettingsStore.load(from: defaults)
        XCTAssertEqual(loaded.theme, .monochrome)
        XCTAssertEqual(loaded.fontSize, EditorSettings.maxFontSize)
        XCTAssertEqual(loaded.defaultExtension, "swift")
        XCTAssertTrue(loaded.appLockEnabled)
        XCTAssertTrue(loaded.includeInDeviceBackup)

        defaults.set(Data("[]".utf8), forKey: EditorSettingsStore.storageKey)
        XCTAssertEqual(EditorSettingsStore.load(from: defaults), .default)

        let unknown = """
        {"theme":"neon","fontSize":8,"defaultExtension":"../x","appLockEnabled":false}
        """
        defaults.set(Data(unknown.utf8), forKey: EditorSettingsStore.storageKey)
        let recovered = EditorSettingsStore.load(from: defaults)
        XCTAssertEqual(recovered.theme, .system)
        XCTAssertEqual(recovered.fontSize, EditorSettings.minFontSize)
        XCTAssertEqual(recovered.defaultExtension, "txt")
        XCTAssertTrue(recovered.useMonospace)
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

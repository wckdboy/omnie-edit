import Foundation
import Observation
import OmnieDocumentKit
import OmnieEditCore

@MainActor
@Observable
final class EditorModel {
    let documentID: String
    private let store: DocumentStore
    private let onDocumentsChanged: () -> Void
    private var session: EditorSession
    private var autosave = AutosaveClock(delay: 0.7)
    private var saveTask: Task<Void, Never>?

    private(set) var name: String
    private(set) var fileExtension: String
    private(set) var saveError: String?
    var isFinding = false
    var findQuery = "" {
        didSet { refreshMatches(scroll: true) }
    }
    var caseInsensitive = true {
        didSet { refreshMatches(scroll: true) }
    }
    private(set) var matches: [TextSearch.Match] = []
    var matchIndex = 0
    var selectionNonce = 0

    var draft: String { session.draft }
    var isDirty: Bool { session.isDirty }
    var language: SourceLanguage { SourceLanguage.detect(fileExtension: fileExtension) }

    init(documentID: String, store: DocumentStore, onDocumentsChanged: @escaping () -> Void) throws {
        self.documentID = documentID
        self.store = store
        self.onDocumentsChanged = onDocumentsChanged
        let text = try store.read(id: documentID)
        guard let document = try store.documents().first(where: { $0.id == documentID }) else {
            throw OmnieDocumentError.documentNotFound(id: documentID)
        }
        name = document.name
        fileExtension = document.fileExtension
        session = EditorSession(text: text)
    }

    func replaceDraft(_ text: String) {
        guard text != session.draft else { return }
        session.draft = text
        refreshMatches(scroll: false)
        scheduleAutosave()
    }

    func report(_ message: String) {
        saveError = message
    }

    func saveNow() {
        autosave.cancel()
        let pending = saveTask
        saveTask = nil
        pending?.cancel()
        let snapshot = session.draft
        do {
            try store.write(id: documentID, contents: snapshot)
            session.noteSaved(snapshot: snapshot)
            saveError = nil
            onDocumentsChanged()
        } catch {
            saveError = error.localizedDescription
        }
    }

    func rename(to desired: String) {
        do {
            let updated = try store.rename(id: documentID, to: desired)
            name = updated.name
            fileExtension = updated.fileExtension
            saveError = nil
            onDocumentsChanged()
        } catch {
            saveError = error.localizedDescription
        }
    }

    func stepMatch(_ step: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = TextSearch.wrappedIndex(current: matchIndex, count: matches.count, step: step)
        selectionNonce += 1
    }

    private func refreshMatches(scroll: Bool) {
        matches = TextSearch.matches(in: session.draft, query: findQuery, caseInsensitive: caseInsensitive)
        if matches.isEmpty {
            matchIndex = 0
        } else if matchIndex >= matches.count {
            matchIndex = 0
        }
        if scroll, !matches.isEmpty {
            selectionNonce += 1
        }
    }

    private func scheduleAutosave() {
        let pending = saveTask
        saveTask = nil
        pending?.cancel()
        autosave.markEdited(at: Date())
        let delay = autosave.delay
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard autosave.isDue(at: Date()) else { return }
            saveNow()
        }
    }
}

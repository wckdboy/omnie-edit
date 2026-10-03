import Foundation
import Observation
import OmnieEditCore
import SwiftUI

/// Application-wide state for files, projects, tabs, and user preferences.
///
/// The model never owns a private copy of a user's document. Every editor tab
/// points at the exact URL selected in Files or discovered inside a project.
@MainActor
@Observable
final class AppModel {
    static let maximumOpenTabs = 8

    private let recentStore: RecentWorkspaceStore
    private let fileSystem: ProjectFileSystem
    private let textFile: CoordinatedTextFile
    private let gitService: GitRepositoryService
    private let gitIdentityStore: GitIdentityStore
    private let defaults: UserDefaults

    @ObservationIgnored
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    private(set) var recents: [RecentWorkspace]
    private(set) var tabs: [EditorTab] = []
    private(set) var projectRoot: URL?
    private(set) var currentFolder: URL?
    private(set) var projectEntries: [ProjectEntry] = []
    private(set) var projectUsesGit = false
    private(set) var gitStatus: [GitStatusItem] = []

    var selectedTabID: UUID?
    var settings: EditorSettings {
        didSet { persistSettings() }
    }
    var lastError: String?
    var gitIdentity: GitIdentity?

    init(
        defaults: UserDefaults = .standard,
        recentStore: RecentWorkspaceStore? = nil,
        fileSystem: ProjectFileSystem = ProjectFileSystem(),
        textFile: CoordinatedTextFile = CoordinatedTextFile()
    ) {
        self.defaults = defaults
        self.recentStore = recentStore ?? RecentWorkspaceStore(defaults: defaults)
        self.fileSystem = fileSystem
        self.textFile = textFile
        gitService = GitRepositoryService()
        gitIdentityStore = GitIdentityStore()
        settings = EditorSettingsStore.load(from: defaults)
        recents = self.recentStore.load()
        gitIdentity = gitIdentityStore.load()
    }

    var selectedTab: EditorTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var isAtProjectRoot: Bool {
        currentFolder?.standardizedFileURL == projectRoot?.standardizedFileURL
    }

    var projectTitle: String {
        projectRoot?.lastPathComponent ?? "Project"
    }

    var currentFolderTitle: String {
        currentFolder?.lastPathComponent ?? projectTitle
    }

    func tab(id: UUID) -> EditorTab? {
        tabs.first { $0.id == id }
    }

    // MARK: - Recent files and projects

    @discardableResult
    func openPickedFile(_ url: URL) -> UUID? {
        openFile(url, accessURL: url, addToRecents: true)
    }

    func openPickedProject(_ url: URL) -> Bool {
        do {
            let values = try WorkspaceBookmark.withAccess(to: url) {
                try url.resourceValues(forKeys: [.isDirectoryKey])
            }
            guard values.isDirectory == true else {
                throw WorkspaceError.unsupportedItem(name: url.lastPathComponent)
            }
            projectRoot = url
            currentFolder = url
            try remember(url: url, kind: .project)
            try reloadProjectFolder()
            Task { await refreshGitStatus() }
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Resolves a recent bookmark. Stale bookmarks are refreshed immediately.
    func openRecent(_ item: RecentWorkspace) -> RecentOpenResult? {
        do {
            let resolved = try WorkspaceBookmark.resolve(item.bookmark)
            if resolved.isStale {
                try remember(url: resolved.url, kind: item.kind, replacing: item.id)
            } else {
                touchRecent(id: item.id)
            }
            switch item.kind {
            case .file:
                guard let tabID = openFile(
                    resolved.url,
                    accessURL: resolved.url,
                    addToRecents: false
                ) else {
                    return nil
                }
                tab(id: tabID)?.recentID = item.id
                return .file(tabID)
            case .project:
                guard openPickedProject(resolved.url) else { return nil }
                return .project
            }
        } catch {
            report(error)
            return nil
        }
    }

    /// Removes an entry from recents without touching the file or folder.
    func removeRecent(id: UUID) {
        recents.removeAll { $0.id == id }
        recentStore.save(recents)
    }

    // MARK: - Project browsing

    func reloadProjectFolder() throws {
        guard let projectRoot, let currentFolder else { return }
        projectEntries = try fileSystem.children(of: currentFolder, projectRoot: projectRoot)
    }

    func enterFolder(_ url: URL) {
        currentFolder = url
        do {
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func searchProject(for query: String) async -> [ProjectEntry] {
        guard let projectRoot else { return [] }
        let fileSystem = fileSystem
        do {
            return try await Task.detached(priority: .userInitiated) {
                try fileSystem.search(for: query, projectRoot: projectRoot)
            }.value
        } catch {
            report(error)
            return []
        }
    }

    // MARK: - Local Git

    func refreshGitStatus() async {
        guard let projectRoot else { return }
        let service = gitService
        let usesGit = await Task.detached(priority: .utility) {
            service.isRepository(at: projectRoot)
        }.value
        projectUsesGit = usesGit
        guard usesGit else {
            gitStatus = []
            return
        }
        do {
            gitStatus = try await Task.detached(priority: .utility) {
                try service.status(at: projectRoot)
            }.value
        } catch {
            report(error)
        }
    }

    func enableGit() async {
        guard let projectRoot else { return }
        do {
            let service = gitService
            try await Task.detached(priority: .utility) {
                try service.createRepository(at: projectRoot)
            }.value
            await refreshGitStatus()
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func stageGitFile(path: String) async {
        guard let projectRoot else { return }
        do {
            let service = gitService
            try await Task.detached(priority: .utility) {
                try service.stage(path: path, at: projectRoot)
            }.value
            await refreshGitStatus()
        } catch {
            report(error)
        }
    }

    func gitDiff(path: String) async -> GitFileDiff? {
        guard let projectRoot else { return nil }
        do {
            let service = gitService
            return try await Task.detached(priority: .userInitiated) {
                try service.diff(for: path, at: projectRoot)
            }.value
        } catch {
            report(error)
            return nil
        }
    }

    func commitGitChanges(message: String) async -> Bool {
        guard let projectRoot else { return false }
        do {
            let service = gitService
            let identity = gitIdentity
            try await Task.detached(priority: .utility) {
                try service.commit(message: message, identity: identity, at: projectRoot)
            }.value
            await refreshGitStatus()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func discardGitChanges(path: String) async {
        guard let projectRoot else { return }
        do {
            let service = gitService
            try await Task.detached(priority: .utility) {
                try service.discard(path: path, at: projectRoot)
            }.value
            await refreshGitStatus()
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func saveGitIdentity(name: String, email: String) {
        do {
            let identity = GitIdentity(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try gitIdentityStore.save(identity)
            gitIdentity = identity
        } catch {
            report(error)
        }
    }

    func leaveFolder() {
        guard let projectRoot, let currentFolder, !isAtProjectRoot else { return }
        let parent = currentFolder.deletingLastPathComponent()
        guard parent.standardizedFileURL.path.hasPrefix(projectRoot.standardizedFileURL.path) else {
            return
        }
        enterFolder(parent)
    }

    @discardableResult
    func openProjectFile(_ url: URL) -> UUID? {
        guard let projectRoot else { return nil }
        return openFile(url, accessURL: projectRoot, addToRecents: false)
    }

    func createProjectFile(named name: String) {
        guard let projectRoot, let currentFolder else { return }
        do {
            let url = try fileSystem.createFile(
                named: name,
                in: currentFolder,
                projectRoot: projectRoot
            )
            try reloadProjectFolder()
            _ = openProjectFile(url)
        } catch {
            report(error)
        }
    }

    func createProjectFolder(named name: String) {
        guard let projectRoot, let currentFolder else { return }
        do {
            _ = try fileSystem.createFolder(
                named: name,
                in: currentFolder,
                projectRoot: projectRoot
            )
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func renameProjectItem(_ entry: ProjectEntry, to name: String) {
        guard let projectRoot else { return }
        do {
            let destination = try fileSystem.rename(entry.url, to: name, projectRoot: projectRoot)
            updateOpenTabURLs(from: entry.url, to: destination)
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func duplicateProjectItem(_ entry: ProjectEntry) {
        guard let projectRoot else { return }
        do {
            _ = try fileSystem.duplicate(entry.url, projectRoot: projectRoot)
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func moveDestinations(for entry: ProjectEntry) async -> [ProjectFolderDestination] {
        guard let projectRoot else { return [] }
        let fileSystem = fileSystem
        do {
            let folders = try await Task.detached(priority: .userInitiated) {
                try fileSystem.folders(
                    in: projectRoot,
                    excluding: entry.isDirectory ? entry.url : nil
                )
            }.value
            let currentFolder = entry.url.deletingLastPathComponent().standardizedFileURL
            return folders.filter {
                $0.standardizedFileURL != currentFolder
            }.map { folder in
                let title: String
                if folder.standardizedFileURL == projectRoot.standardizedFileURL {
                    title = "Project Root"
                } else {
                    title = folder.path.replacingOccurrences(
                        of: projectRoot.path + "/",
                        with: ""
                    )
                }
                return ProjectFolderDestination(url: folder, title: title)
            }
        } catch {
            report(error)
            return []
        }
    }

    func moveProjectItem(_ entry: ProjectEntry, to folderURL: URL) {
        guard let projectRoot else { return }
        do {
            let destination = try fileSystem.move(
                entry.url,
                to: folderURL,
                projectRoot: projectRoot
            )
            updateOpenTabURLs(from: entry.url, to: destination)
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    func deleteProjectItem(_ entry: ProjectEntry) {
        guard let projectRoot else { return }
        do {
            try fileSystem.delete(entry.url, projectRoot: projectRoot)
            closeTabs(below: entry.url)
            try reloadProjectFolder()
        } catch {
            report(error)
        }
    }

    // MARK: - Editor tabs

    @discardableResult
    private func openFile(
        _ url: URL,
        accessURL: URL,
        addToRecents: Bool
    ) -> UUID? {
        if let existing = tabs.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            selectedTabID = existing.id
            return existing.id
        }
        guard tabs.count < Self.maximumOpenTabs else {
            lastError = "Close a tab before opening another file. Omnie Edit keeps up to eight files open."
            return nil
        }
        do {
            let text = try textFile.read(from: url, accessing: accessURL)
            let tab = EditorTab(url: url, accessURL: accessURL, text: text)
            tabs.append(tab)
            selectedTabID = tab.id
            if addToRecents {
                tab.recentID = try remember(url: url, kind: .file)
            }
            return tab.id
        } catch {
            report(error)
            return nil
        }
    }

    /// Renames the file backing an open tab, including changing its
    /// extension. Works whether the tab belongs to an open project folder or
    /// was opened standalone from Files.
    func renameOpenFile(_ tab: EditorTab, to name: String) {
        if let projectRoot, tab.accessURL.standardizedFileURL == projectRoot.standardizedFileURL {
            do {
                let destination = try fileSystem.rename(tab.url, to: name, projectRoot: projectRoot)
                updateOpenTabURLs(from: tab.url, to: destination)
                try reloadProjectFolder()
            } catch {
                report(error)
            }
            return
        }

        do {
            let destination = try fileSystem.renameStandaloneFile(
                tab.url,
                to: name,
                accessURL: tab.accessURL
            )
            tab.url = destination
            tab.accessURL = destination
            if let recentID = tab.recentID {
                _ = try? remember(url: destination, kind: .file, replacing: recentID)
            }
        } catch {
            report(error)
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closeTab(id: UUID) {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            selectedTabID = tabs.last?.id
        }
    }

    /// Saves pending edits before removing a user-closed tab.
    func saveAndCloseTab(id: UUID) async {
        guard let tab = tab(id: id) else { return }
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        if tab.isDirty {
            await save(tab)
        }
        guard tab.saveError == nil else { return }
        closeTab(id: id)
    }

    func textDidChange(in tab: EditorTab) {
        guard tab.isDirty else { return }
        pendingSaves[tab.id]?.cancel()
        pendingSaves[tab.id] = Task { [weak self, weak tab] in
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, let self, let tab else { return }
                await self.save(tab)
            } catch {
                // Cancellation is expected whenever another keystroke restarts
                // the debounce timer.
            }
        }
    }

    func saveSelectedTab() async {
        guard let selectedTab else { return }
        await save(selectedTab)
    }

    func flushAllTabs() async {
        for task in pendingSaves.values {
            task.cancel()
        }
        pendingSaves.removeAll()
        for tab in tabs where tab.isDirty {
            await save(tab)
        }
    }

    private func save(_ tab: EditorTab) async {
        let snapshot = tab.text
        let url = tab.url
        let accessURL = tab.accessURL
        do {
            let writer = textFile
            try await Task.detached(priority: .utility) {
                try writer.write(snapshot, to: url, accessing: accessURL)
            }.value
            if tab.text == snapshot {
                tab.markSaved(snapshot)
            }
        } catch {
            tab.saveError = error.localizedDescription
            report(error)
        }
    }

    // MARK: - Settings and errors

    func handle(scenePhase: ScenePhase) {
        guard scenePhase != .active else { return }
        Task {
            await flushAllTabs()
        }
    }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// Applies and immediately persists the one-handed layout preference.
    func setPreferredHand(_ hand: PreferredHand) {
        settings.preferredHand = hand
        persistSettings()
    }

    private func persistSettings() {
        let clamped = settings.clamped()
        if clamped != settings {
            settings = clamped
            return
        }
        EditorSettingsStore.save(clamped, to: defaults)
    }

    @discardableResult
    private func remember(
        url: URL,
        kind: WorkspaceKind,
        replacing id: UUID? = nil
    ) throws -> UUID {
        let bookmark = try WorkspaceBookmark.withAccess(to: url) {
            try WorkspaceBookmark.create(for: url)
        }
        let standardized = url.standardizedFileURL
        recents.removeAll { item in
            if item.id == id { return true }
            guard let resolved = try? WorkspaceBookmark.resolve(item.bookmark) else { return false }
            return resolved.url.standardizedFileURL == standardized
        }
        let resultID = id ?? UUID()
        recents.append(
            RecentWorkspace(
                id: resultID,
                kind: kind,
                displayName: url.lastPathComponent,
                bookmark: bookmark
            )
        )
        recents.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        recentStore.save(recents)
        return resultID
    }

    private func touchRecent(id: UUID) {
        guard let index = recents.firstIndex(where: { $0.id == id }) else { return }
        recents[index].lastOpenedAt = Date()
        recents.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        recentStore.save(recents)
    }

    private func updateOpenTabURLs(from source: URL, to destination: URL) {
        let sourcePath = source.standardizedFileURL.path
        for tab in tabs {
            let tabPath = tab.url.standardizedFileURL.path
            if tabPath == sourcePath {
                tab.url = destination
            } else if tabPath.hasPrefix(sourcePath + "/") {
                let relativePath = String(tabPath.dropFirst(sourcePath.count + 1))
                tab.url = destination.appendingPathComponent(relativePath)
            }
        }
    }

    private func closeTabs(below deletedURL: URL) {
        let deletedPath = deletedURL.standardizedFileURL.path
        let ids = tabs.filter {
            let path = $0.url.standardizedFileURL.path
            return path == deletedPath || path.hasPrefix(deletedPath + "/")
        }.map(\.id)
        for id in ids {
            closeTab(id: id)
        }
    }
}

struct ProjectFolderDestination: Identifiable, Hashable {
    let url: URL
    let title: String

    var id: URL { url }
}

enum RecentOpenResult {
    case file(UUID)
    case project
}

/// Mutable state for one open editor tab.
@MainActor
@Observable
final class EditorTab: Identifiable {
    let id: UUID
    var url: URL
    var accessURL: URL
    var text: String
    private(set) var savedText: String
    var saveError: String?
    /// The id of this file's entry in Recents, if it has one. Lets a rename
    /// update that entry directly instead of re-deriving it from a bookmark.
    var recentID: UUID?

    init(id: UUID = UUID(), url: URL, accessURL: URL, text: String) {
        self.id = id
        self.url = url
        self.accessURL = accessURL
        self.text = text
        savedText = text
    }

    var name: String { url.lastPathComponent }
    var language: EditorLanguage { EditorLanguage(fileURL: url) }
    var isDirty: Bool { text != savedText }

    func markSaved(_ text: String) {
        savedText = text
        saveError = nil
    }
}

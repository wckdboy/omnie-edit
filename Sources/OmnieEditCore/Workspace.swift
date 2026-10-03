import Foundation

/// The kind of resource shown in the library's recent-items list.
public enum WorkspaceKind: String, Codable, Sendable {
    case file
    case project
}

/// A durable reference to a file or folder selected through the system picker.
///
/// The URL itself is deliberately not persisted. URLs returned by Files can stop
/// working after relaunch; bookmark data is the supported way to regain access.
public struct RecentWorkspace: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: WorkspaceKind
    public var displayName: String
    public var bookmark: Data
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        kind: WorkspaceKind,
        displayName: String,
        bookmark: Data,
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmark = bookmark
        self.lastOpenedAt = lastOpenedAt
    }
}

/// Persists the small recent-items index. File contents never enter UserDefaults.
public struct RecentWorkspaceStore {
    public static let storageKey = "omnie.edit.recent-workspaces.v1"

    private let defaults: UserDefaults
    private let limit: Int

    public init(defaults: UserDefaults = .standard, limit: Int = 20) {
        self.defaults = defaults
        self.limit = max(1, limit)
    }

    public func load() -> [RecentWorkspace] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([RecentWorkspace].self, from: data) else {
            return []
        }
        return decoded
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .prefix(limit)
            .map { $0 }
    }

    public func save(_ items: [RecentWorkspace]) {
        let trimmed = items
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .prefix(limit)
            .map { $0 }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

public struct ResolvedBookmark: Sendable {
    public let url: URL
    public let isStale: Bool
}

/// Creates and resolves the bookmarks used to reopen Files selections.
public enum WorkspaceBookmark {
    public static func create(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        // iOS picker URLs carry an implicit security scope. Apple's directory
        // access guidance recommends a minimal bookmark to persist that URL.
        return try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    public static func resolve(_ data: Data) throws -> ResolvedBookmark {
        var stale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #endif
        return ResolvedBookmark(url: url, isStale: stale)
    }

    /// Keeps a picker URL's security scope balanced for the duration of `body`.
    public static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }
}

public enum WorkspaceError: LocalizedError, Equatable {
    case fileTooLarge(name: String, maximumBytes: Int)
    case notUTF8(name: String)
    case unsupportedItem(name: String)
    case invalidName
    case invalidMove(String)
    case fileAlreadyExists(name: String)
    case coordinatedAccessFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .fileTooLarge(name, maximumBytes):
            let megabytes = maximumBytes / 1_048_576
            return "\(name) is larger than the \(megabytes) MB editing limit."
        case let .notUTF8(name):
            return "\(name) is not a UTF-8 text file."
        case let .unsupportedItem(name):
            return "\(name) is not a regular file or folder."
        case .invalidName:
            return "Enter a name without slashes or control characters."
        case let .invalidMove(message):
            return message
        case let .fileAlreadyExists(name):
            return "An item named \(name) already exists."
        case let .coordinatedAccessFailed(message):
            return message
        }
    }
}

/// Reads and writes external text files without racing the Files app or iCloud.
public struct CoordinatedTextFile: Sendable {
    public static let defaultMaximumBytes = 2 * 1_048_576

    public let maximumBytes: Int

    public init(maximumBytes: Int = Self.defaultMaximumBytes) {
        self.maximumBytes = maximumBytes
    }

    public func read(from url: URL) throws -> String {
        try read(from: url, accessing: url)
    }

    /// Reads `url` while holding the security scope granted for `accessURL`.
    /// Project children use the bookmarked project root as their access URL.
    public func read(from url: URL, accessing accessURL: URL) throws -> String {
        try WorkspaceBookmark.withAccess(to: accessURL) {
            var coordinationError: NSError?
            var result: Result<String, Error>?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                result = Result {
                    let values = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true else {
                        throw WorkspaceError.unsupportedItem(name: coordinatedURL.lastPathComponent)
                    }
                    if let size = values.fileSize, size > maximumBytes {
                        throw WorkspaceError.fileTooLarge(
                            name: coordinatedURL.lastPathComponent,
                            maximumBytes: maximumBytes
                        )
                    }
                    let data = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                    guard data.count <= maximumBytes else {
                        throw WorkspaceError.fileTooLarge(
                            name: coordinatedURL.lastPathComponent,
                            maximumBytes: maximumBytes
                        )
                    }
                    return try decodeUTF8(data, name: coordinatedURL.lastPathComponent)
                }
            }
            if let coordinationError {
                throw coordinationError
            }
            guard let result else {
                throw WorkspaceError.coordinatedAccessFailed("The file could not be read.")
            }
            return try result.get()
        }
    }

    public func write(_ text: String, to url: URL) throws {
        try write(text, to: url, accessing: url)
    }

    /// Writes `url` while holding the security scope granted for `accessURL`.
    public func write(_ text: String, to url: URL, accessing accessURL: URL) throws {
        let data = Data(text.utf8)
        guard data.count <= maximumBytes else {
            throw WorkspaceError.fileTooLarge(name: url.lastPathComponent, maximumBytes: maximumBytes)
        }
        try WorkspaceBookmark.withAccess(to: accessURL) {
            var coordinationError: NSError?
            var writeError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let coordinationError {
                throw coordinationError
            }
            if let writeError {
                throw writeError
            }
        }
    }

    private func decodeUTF8(_ data: Data, name: String) throws -> String {
        let payload: Data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload = data.dropFirst(3)
        } else {
            payload = data
        }
        guard let text = String(data: payload, encoding: .utf8) else {
            throw WorkspaceError.notUTF8(name: name)
        }
        return text
    }
}

public struct ProjectEntry: Identifiable, Equatable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let byteCount: Int?
    public let modifiedAt: Date?
}

/// Performs the file operations used by the one-level-at-a-time project browser.
public struct ProjectFileSystem: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    public func children(of folderURL: URL, projectRoot: URL) throws -> [ProjectEntry] {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]
            let urls = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
            let gitDirectory = projectRoot.appendingPathComponent(".git", isDirectory: true)
            let ignoreRules = fileManager.fileExists(atPath: gitDirectory.path)
                ? GitIgnoreRules(projectRoot: projectRoot, fileManager: fileManager)
                : nil
            return try urls.compactMap { url in
                let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                if url.lastPathComponent == ".git" || ignoreRules?.ignores(relativePath) == true {
                    return nil
                }
                let values = try url.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true,
                      values.isDirectory == true || values.isRegularFile == true else {
                    return nil
                }
                return ProjectEntry(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: values.isDirectory == true,
                    byteCount: values.fileSize,
                    modifiedAt: values.contentModificationDate
                )
            }.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Searches the complete project while applying the same visibility rules
    /// as the browser. Results are capped so a broad query cannot flood the UI.
    public func search(
        for query: String,
        projectRoot: URL,
        maximumResults: Int = 100
    ) throws -> [ProjectEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        return try WorkspaceBookmark.withAccess(to: projectRoot) {
            let keys: [URLResourceKey] = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]
            guard let enumerator = fileManager.enumerator(
                at: projectRoot,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                throw WorkspaceError.coordinatedAccessFailed("The project could not be searched.")
            }

            let gitDirectory = projectRoot.appendingPathComponent(".git", isDirectory: true)
            let ignoreRules = fileManager.fileExists(atPath: gitDirectory.path)
                ? GitIgnoreRules(projectRoot: projectRoot, fileManager: fileManager)
                : nil
            var results: [ProjectEntry] = []
            for case let url as URL in enumerator {
                let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                if relativePath == ".git" || relativePath.hasPrefix(".git/") {
                    if url.lastPathComponent == ".git" {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if ignoreRules?.ignores(relativePath) == true {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    if values?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard url.lastPathComponent.localizedCaseInsensitiveContains(needle) else { continue }

                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isSymbolicLink != true,
                      values.isDirectory == true || values.isRegularFile == true else {
                    continue
                }
                results.append(
                    ProjectEntry(
                        url: url,
                        name: relativePath,
                        isDirectory: values.isDirectory == true,
                        byteCount: values.fileSize,
                        modifiedAt: values.contentModificationDate
                    )
                )
                if results.count >= maximumResults { break }
            }
            return results.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Returns every visible destination folder in the project.
    ///
    /// When moving a folder, that folder and its descendants are excluded to
    /// prevent a recursive move into itself.
    public func folders(in projectRoot: URL, excluding sourceURL: URL? = nil) throws -> [URL] {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            let root = projectRoot.standardizedFileURL
            let source = sourceURL?.standardizedFileURL
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                throw WorkspaceError.coordinatedAccessFailed("The project folders could not be read.")
            }

            let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
            let ignoreRules = fileManager.fileExists(atPath: gitDirectory.path)
                ? GitIgnoreRules(projectRoot: root, fileManager: fileManager)
                : nil
            var folders = [root]

            for case let url as URL in enumerator {
                let standardizedURL = url.standardizedFileURL
                let relativePath = standardizedURL.path.replacingOccurrences(
                    of: root.path + "/",
                    with: ""
                )
                let values = try standardizedURL.resourceValues(forKeys: Set(keys))
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }

                if relativePath == ".git" || relativePath.hasPrefix(".git/") {
                    enumerator.skipDescendants()
                    continue
                }
                if ignoreRules?.ignores(relativePath) == true {
                    enumerator.skipDescendants()
                    continue
                }
                if let source,
                   standardizedURL == source || Self.isDescendant(standardizedURL, of: source) {
                    enumerator.skipDescendants()
                    continue
                }
                folders.append(standardizedURL)
            }

            return folders.sorted {
                let left = $0.path.replacingOccurrences(of: root.path, with: "")
                let right = $1.path.replacingOccurrences(of: root.path, with: "")
                return left.localizedStandardCompare(right) == .orderedAscending
            }
        }
    }

    public func createFile(named name: String, in folderURL: URL, projectRoot: URL) throws -> URL {
        let validated = try validatedName(name)
        let destination = folderURL.appendingPathComponent(validated, isDirectory: false)
        return try createItem(at: destination, projectRoot: projectRoot) {
            try Data().write(to: destination, options: .withoutOverwriting)
        }
    }

    public func createFolder(named name: String, in folderURL: URL, projectRoot: URL) throws -> URL {
        let validated = try validatedName(name)
        let destination = folderURL.appendingPathComponent(validated, isDirectory: true)
        return try createItem(at: destination, projectRoot: projectRoot) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        }
    }

    public func rename(_ url: URL, to newName: String, projectRoot: URL) throws -> URL {
        let validated = try validatedName(newName)
        let destination = url.deletingLastPathComponent().appendingPathComponent(
            validated,
            isDirectory: url.hasDirectoryPath
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceError.fileAlreadyExists(name: validated)
        }
        return try WorkspaceBookmark.withAccess(to: projectRoot) {
            try fileManager.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// Renames a file that was opened on its own (no project folder), such as
    /// one picked directly from Files. There is no project-root bookmark to
    /// lean on here, so access is held on the file's own security scope, and
    /// a fresh bookmark for the renamed path is minted while that scope is
    /// still open — the returned URL carries that bookmark's scope token, so
    /// callers can keep using it for later reads and writes.
    public func renameStandaloneFile(_ url: URL, to newName: String, accessURL: URL) throws -> URL {
        let validated = try validatedName(newName)
        let destination = url.deletingLastPathComponent().appendingPathComponent(
            validated,
            isDirectory: url.hasDirectoryPath
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceError.fileAlreadyExists(name: validated)
        }
        return try WorkspaceBookmark.withAccess(to: accessURL) {
            try fileManager.moveItem(at: url, to: destination)
            let bookmark = try WorkspaceBookmark.create(for: destination)
            return try WorkspaceBookmark.resolve(bookmark).url
        }
    }

    public func move(_ url: URL, to folderURL: URL, projectRoot: URL) throws -> URL {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            let root = projectRoot.standardizedFileURL
            let source = url.standardizedFileURL
            let destinationFolder = folderURL.standardizedFileURL

            guard source != root,
                  Self.isContained(source, in: root),
                  Self.isContained(destinationFolder, in: root) else {
                throw WorkspaceError.invalidMove("Items can only be moved within the open project.")
            }

            let folderValues = try destinationFolder.resourceValues(forKeys: [.isDirectoryKey])
            guard folderValues.isDirectory == true else {
                throw WorkspaceError.invalidMove("Choose a folder inside the open project.")
            }

            let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey])
            if sourceValues.isDirectory == true,
               destinationFolder == source || Self.isDescendant(destinationFolder, of: source) {
                throw WorkspaceError.invalidMove("A folder cannot be moved inside itself.")
            }

            let destination = destinationFolder.appendingPathComponent(
                source.lastPathComponent,
                isDirectory: sourceValues.isDirectory == true
            )
            guard destination != source else { return source }
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw WorkspaceError.fileAlreadyExists(name: source.lastPathComponent)
            }

            try fileManager.moveItem(at: source, to: destination)
            return destination
        }
    }

    public func duplicate(_ url: URL, projectRoot: URL) throws -> URL {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            let destination = uniqueCopyURL(for: url)
            try fileManager.copyItem(at: url, to: destination)
            return destination
        }
    }

    public func delete(_ url: URL, projectRoot: URL) throws {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        candidate.standardizedFileURL.path.hasPrefix(parent.standardizedFileURL.path + "/")
    }

    private func createItem(at destination: URL, projectRoot: URL, operation: () throws -> Void) throws -> URL {
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceError.fileAlreadyExists(name: destination.lastPathComponent)
        }
        return try WorkspaceBookmark.withAccess(to: projectRoot) {
            try operation()
            return destination
        }
    }

    private func validatedName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasControlCharacter = name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(":"),
              !hasControlCharacter else {
            throw WorkspaceError.invalidName
        }
        return name
    }

    private func uniqueCopyURL(for source: URL) -> URL {
        let folder = source.deletingLastPathComponent()
        let extensionName = source.pathExtension
        let baseName = source.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            var candidate = folder.appendingPathComponent(baseName + suffix)
            if !extensionName.isEmpty {
                candidate.appendPathExtension(extensionName)
            }
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}

/// Small, deterministic `.gitignore` matcher for project browsing.
///
/// It supports comments, negation, anchored paths, directory rules, `*`, `**`,
/// and `?`. Git itself remains the authority for status once Git support is on.
struct GitIgnoreRules {
    private struct Rule {
        let regex: NSRegularExpression
        let negated: Bool
    }

    private let rules: [Rule]

    init(projectRoot: URL, fileManager: FileManager) {
        let url = projectRoot.appendingPathComponent(".gitignore")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            rules = []
            return
        }
        rules = text.split(whereSeparator: \ .isNewline).compactMap { rawLine in
            var pattern = rawLine.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty, !pattern.hasPrefix("#") else { return nil }
            let negated = pattern.removeFirst(if: "!")
            let directoryOnly = pattern.hasSuffix("/")
            if directoryOnly { pattern.removeLast() }
            let anchored = pattern.hasPrefix("/")
            if anchored { pattern.removeFirst() }
            guard !pattern.isEmpty else { return nil }
            let expression = Self.regularExpression(
                for: pattern,
                anchored: anchored,
                directoryOnly: directoryOnly
            )
            guard let regex = try? NSRegularExpression(pattern: expression) else { return nil }
            return Rule(regex: regex, negated: negated)
        }
    }

    func ignores(_ relativePath: String) -> Bool {
        var ignored = false
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        for rule in rules where rule.regex.firstMatch(in: relativePath, range: range) != nil {
            ignored = !rule.negated
        }
        return ignored
    }

    private static func regularExpression(
        for pattern: String,
        anchored: Bool,
        directoryOnly: Bool
    ) -> String {
        var result = anchored || pattern.contains("/") ? "^" : "(^|.*/)"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    result += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                result += "[^/]*"
            } else if character == "?" {
                result += "[^/]"
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = pattern.index(after: index)
        }
        result += directoryOnly ? "(/.*)?$" : "$"
        return result
    }
}

private extension String {
    mutating func removeFirst(if character: Character) -> Bool {
        guard first == character else { return false }
        removeFirst()
        return true
    }
}

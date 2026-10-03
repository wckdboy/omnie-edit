#if os(iOS)
import Foundation
import Security
import SwiftGitX

public enum GitFileState: String, Sendable {
    case added
    case changed
    case deleted
    case renamed
    case untracked
    case conflicted
}

public struct GitStatusItem: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let states: [GitFileState]
    public let isStaged: Bool
}

public struct GitPatchLine: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        case context
        case addition
        case deletion
        case header
    }

    public let id = UUID()
    public let kind: Kind
    public let text: String
}

public struct GitFileDiff: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let lines: [GitPatchLine]
}

public struct GitIdentity: Equatable, Sendable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

public enum GitServiceError: LocalizedError, Equatable {
    case notRepository
    case emptyCommitMessage
    case missingIdentity
    case pathNotFound

    public var errorDescription: String? {
        switch self {
        case .notRepository:
            "This folder is not a Git repository."
        case .emptyCommitMessage:
            "Enter a commit message before committing."
        case .missingIdentity:
            "Add a Git name and email in Settings before committing."
        case .pathNotFound:
            "That changed file is no longer available."
        }
    }
}

/// Local Git operations for a security-scoped project folder.
///
/// All libgit2 details stay in this file so the application UI deals only in
/// small, stable value types. Remote authentication is intentionally separate.
public struct GitRepositoryService: Sendable {
    public init() {}

    public func isRepository(at projectRoot: URL) -> Bool {
        WorkspaceBookmark.withAccess(to: projectRoot) {
            (try? Repository.open(at: projectRoot)) != nil
        }
    }

    public func createRepository(at projectRoot: URL) throws {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            _ = try Repository.create(at: projectRoot)
        }
    }

    public func status(at projectRoot: URL) throws -> [GitStatusItem] {
        try withRepository(at: projectRoot) { repository in
            try repository.status().compactMap(mapStatus).sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        }
    }

    public func diff(for path: String, at projectRoot: URL) throws -> GitFileDiff {
        try withRepository(at: projectRoot) { repository in
            guard let entry = try repository.status().first(where: { statusPath($0) == path }),
                  let delta = entry.workingTree ?? entry.index,
                  let patch = try repository.patch(from: delta) else {
                throw GitServiceError.pathNotFound
            }

            var lines: [GitPatchLine] = []
            for hunk in patch.hunks {
                lines.append(GitPatchLine(kind: .header, text: hunk.header))
                lines.append(contentsOf: hunk.lines.map { line in
                    GitPatchLine(kind: lineKind(line.type), text: line.type.rawValue + line.content)
                })
            }
            return GitFileDiff(path: path, lines: lines)
        }
    }

    public func stage(path: String, at projectRoot: URL) throws {
        try withRepository(at: projectRoot) { repository in
            try repository.add(path: path)
        }
    }

    public func commit(
        message: String,
        identity: GitIdentity?,
        at projectRoot: URL
    ) throws {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw GitServiceError.emptyCommitMessage }
        guard let identity,
              !identity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !identity.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitServiceError.missingIdentity
        }

        try withRepository(at: projectRoot) { repository in
            try repository.config.set("user.name", to: identity.name)
            try repository.config.set("user.email", to: identity.email)
            try repository.commit(message: trimmedMessage)
        }
    }

    /// Restores a tracked path. An untracked path is deleted because no Git
    /// object exists to restore; callers must confirm this destructive action.
    public func discard(path: String, at projectRoot: URL) throws {
        try withRepository(at: projectRoot) { repository in
            let states = try repository.status(path: path)
            if states.contains(where: { $0 == .workingTreeNew }) {
                let url = projectRoot.appendingPathComponent(path)
                try FileManager.default.removeItem(at: url)
            } else {
                try repository.restore(.workingTree, paths: [path])
            }
        }
    }

    private func withRepository<T>(
        at projectRoot: URL,
        operation: (Repository) throws -> T
    ) throws -> T {
        try WorkspaceBookmark.withAccess(to: projectRoot) {
            guard let repository = try? Repository.open(at: projectRoot) else {
                throw GitServiceError.notRepository
            }
            return try operation(repository)
        }
    }

    private func mapStatus(_ entry: StatusEntry) -> GitStatusItem? {
        guard let path = statusPath(entry) else { return nil }
        var states: [GitFileState] = []
        for status in entry.status {
            let state: GitFileState?
            switch status {
            case .indexNew: state = .added
            case .indexModified, .workingTreeModified, .workingTreeTypeChange, .indexTypeChange: state = .changed
            case .indexDeleted, .workingTreeDeleted: state = .deleted
            case .indexRenamed, .workingTreeRenamed: state = .renamed
            case .workingTreeNew: state = .untracked
            case .conflicted: state = .conflicted
            case .current, .ignored, .workingTreeUnreadable: state = nil
            }
            if let state, !states.contains(state) {
                states.append(state)
            }
        }
        let staged = entry.status.contains { status in
            switch status {
            case .indexNew, .indexModified, .indexDeleted, .indexRenamed, .indexTypeChange: true
            default: false
            }
        }
        return GitStatusItem(path: path, states: states, isStaged: staged)
    }

    private func statusPath(_ entry: StatusEntry) -> String? {
        entry.workingTree?.newFile.path
            ?? entry.workingTree?.oldFile.path
            ?? entry.index?.newFile.path
            ?? entry.index?.oldFile.path
    }

    private func lineKind(_ type: Patch.Hunk.LineType) -> GitPatchLine.Kind {
        switch type {
        case .addition, .additionEOF: .addition
        case .deletion, .deletionEOF: .deletion
        case .context, .contextEOF: .context
        }
    }
}

/// Stores Git identity separately from preferences. Keychain storage keeps the
/// value local to the device and ready for future credential support.
public struct GitIdentityStore: Sendable {
    private let service = "ai.wckd.omnie.edit.git-identity"

    public init() {}

    public func load() -> GitIdentity? {
        guard let data = read(account: "identity"),
              let values = try? JSONDecoder().decode([String: String].self, from: data),
              let name = values["name"],
              let email = values["email"] else {
            return nil
        }
        return GitIdentity(name: name, email: email)
    }

    public func save(_ identity: GitIdentity) throws {
        let data = try JSONEncoder().encode(["name": identity.name, "email": identity.email])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "identity",
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
#endif

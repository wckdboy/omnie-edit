import Foundation
import OmnieDocumentKit

public struct LockedDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var fileExtension: String
    public var byteCount: Int64
    public var modifiedAt: Date

    public init(
        id: String,
        name: String,
        fileExtension: String,
        byteCount: Int64,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

public struct LibraryDocument: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var fileExtension: String
    public var byteCount: Int64
    public var modifiedAt: Date
    public var isLocked: Bool

    public init(
        id: String,
        name: String,
        fileExtension: String,
        byteCount: Int64,
        modifiedAt: Date,
        isLocked: Bool
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
        self.isLocked = isLocked
    }
}

/// Writes the shared catalog peers read, and keeps locked files in a private folder.
public final class DocumentStore {
    public let sharedRoot: URL
    public let privateRoot: URL
    public var includeInDeviceBackup: Bool

    private let writer: FileWriting
    private let backup: BackupMarking
    private let fileManager: FileManager
    private let catalog: OmnieDocumentCatalog

    public init(
        sharedRoot: URL,
        privateRoot: URL,
        includeInDeviceBackup: Bool = false,
        writer: FileWriting = ProtectedFileWriter(),
        backup: BackupMarking = URLResourceBackupMarker(),
        fileManager: FileManager = .default
    ) {
        self.sharedRoot = sharedRoot
        self.privateRoot = privateRoot
        self.includeInDeviceBackup = includeInDeviceBackup
        self.writer = writer
        self.backup = backup
        self.fileManager = fileManager
        self.catalog = OmnieDocumentCatalog(rootURL: sharedRoot)
    }

    public func prepare() throws {
        try DirectorySetup.createProtectedDirectory(sharedRoot, fileManager: fileManager)
        try DirectorySetup.createProtectedDirectory(catalog.documentsDirectory, fileManager: fileManager)
        try DirectorySetup.createProtectedDirectory(privateRoot, fileManager: fileManager)
        try DirectorySetup.createProtectedDirectory(lockedFilesDirectory, fileManager: fileManager)
        try applyBackupPolicy()
        try reconcileCatalog()
    }

    public func documents() throws -> [LibraryDocument] {
        let lockedRecords = try loadLocked().documents
        let lockedIDs = Set(lockedRecords.map(\.id))
        let shared = try catalog.list(fileManager: fileManager).filter { !lockedIDs.contains($0.id) }.map {
            LibraryDocument(
                id: $0.id,
                name: $0.name,
                fileExtension: $0.fileExtension,
                byteCount: $0.byteCount,
                modifiedAt: $0.modifiedAt,
                isLocked: false
            )
        }
        let locked = lockedRecords.map {
            LibraryDocument(
                id: $0.id,
                name: $0.name,
                fileExtension: $0.fileExtension,
                byteCount: $0.byteCount,
                modifiedAt: $0.modifiedAt,
                isLocked: true
            )
        }
        return (shared + locked).sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    public func create(name: String, contents: String, now: Date = Date()) throws -> LibraryDocument {
        let validated = try validatedName(name)
        let unique = OmnieFileName.uniqued(validated, existing: try occupiedNames())
        return try writeNew(id: UUID().uuidString.lowercased(), name: unique, contents: contents, now: now)
    }

    public func importData(_ data: Data, preferredName: String, now: Date = Date()) throws -> LibraryDocument {
        let leaf = OmnieFileName.lastPathComponent(preferredName)
        guard let text = TextFile.decode(data) else {
            throw OmnieDocumentError.notUTF8(name: leaf)
        }
        let candidate: String
        switch OmnieFileName.validateDisplayName(leaf) {
        case let .success(name):
            candidate = name
        case .failure:
            candidate = "Imported.txt"
        }
        return try create(name: candidate, contents: text, now: now)
    }

    public func read(id: String) throws -> String {
        if let summary = try sharedSummary(id: id) {
            return try catalog.read(id: summary.id, fileManager: fileManager)
        }
        if let locked = try lockedSummary(id: id) {
            let url = lockedFileURL(id: locked.id)
            let data = try Data(contentsOf: url)
            guard let text = TextFile.decode(data) else {
                throw OmnieDocumentError.notUTF8(name: locked.name)
            }
            return text
        }
        throw OmnieDocumentError.documentNotFound(id: id)
    }

    public func write(id: String, contents: String, now: Date = Date()) throws {
        let data = TextFile.encode(contents)
        if let summary = try sharedSummary(id: id) {
            let url = try catalog.fileURL(relativePath: summary.relativePath)
            try writeProtected(data, to: url)
            var updated = summary
            let facts = try fileFacts(url, fallbackBytes: Int64(data.count), now: now)
            updated.byteCount = facts.bytes
            updated.modifiedAt = facts.modified
            try replaceShared(id: id, with: updated)
            return
        }
        if var locked = try lockedSummary(id: id) {
            let url = lockedFileURL(id: locked.id)
            try writeProtected(data, to: url)
            let facts = try fileFacts(url, fallbackBytes: Int64(data.count), now: now)
            locked.byteCount = facts.bytes
            locked.modifiedAt = facts.modified
            try replaceLocked(id: id, with: locked)
            return
        }
        throw OmnieDocumentError.documentNotFound(id: id)
    }

    public func rename(id: String, to desired: String) throws -> LibraryDocument {
        let validated = try validatedName(desired)
        var names = try occupiedNames()
        if let current = try documents().first(where: { $0.id == id }) {
            names.remove(current.name)
        } else {
            throw OmnieDocumentError.documentNotFound(id: id)
        }
        let unique = OmnieFileName.uniqued(validated, existing: names)
        if let summary = try sharedSummary(id: id) {
            if summary.name == unique {
                return library(summary, locked: false)
            }
            let destination = try catalog.fileURL(relativePath: unique)
            let source = try catalog.fileURL(relativePath: summary.relativePath)
            if fileManager.fileExists(atPath: destination.path) {
                throw OmnieDocumentError.alreadyExists(unique)
            }
            try fileManager.moveItem(at: source, to: destination)
            try applyExclusion(to: destination)
            var updated = summary
            updated.name = unique
            updated.relativePath = unique
            updated.fileExtension = OmnieFileName.splittingExtension(unique).ext.lowercased()
            try replaceShared(id: id, with: updated)
            return library(updated, locked: false)
        }
        if var locked = try lockedSummary(id: id) {
            locked.name = unique
            locked.fileExtension = OmnieFileName.splittingExtension(unique).ext.lowercased()
            try replaceLocked(id: id, with: locked)
            return LibraryDocument(
                id: locked.id,
                name: locked.name,
                fileExtension: locked.fileExtension,
                byteCount: locked.byteCount,
                modifiedAt: locked.modifiedAt,
                isLocked: true
            )
        }
        throw OmnieDocumentError.documentNotFound(id: id)
    }

    public func delete(id: String) throws {
        if let summary = try sharedSummary(id: id) {
            let url = try catalog.fileURL(relativePath: summary.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try removeShared(id: id)
            return
        }
        if try lockedSummary(id: id) != nil {
            let url = lockedFileURL(id: id)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try removeLocked(id: id)
            return
        }
        throw OmnieDocumentError.documentNotFound(id: id)
    }

    /// Moves a shared document into the private folder and drops it from the catalog.
    public func lock(id: String) throws {
        guard let summary = try sharedSummary(id: id) else {
            if try lockedSummary(id: id) != nil {
                return
            }
            throw OmnieDocumentError.documentNotFound(id: id)
        }
        let source = try catalog.fileURL(relativePath: summary.relativePath)
        let data = try Data(contentsOf: source)
        let destination = lockedFileURL(id: summary.id)
        try writeProtected(data, to: destination)
        var manifest = try loadLocked()
        manifest.documents.removeAll { $0.id == id }
        manifest.documents.append(
            LockedDocument(
                id: summary.id,
                name: summary.name,
                fileExtension: summary.fileExtension,
                byteCount: summary.byteCount,
                modifiedAt: summary.modifiedAt
            )
        )
        try saveLocked(manifest)
        try fileManager.removeItem(at: source)
        try removeShared(id: id)
    }

    /// Returns a locked document to the shared catalog so peers can read it again.
    public func unlock(id: String) throws -> LibraryDocument {
        guard let locked = try lockedSummary(id: id) else {
            if let summary = try sharedSummary(id: id) {
                return library(summary, locked: false)
            }
            throw OmnieDocumentError.documentNotFound(id: id)
        }
        let source = lockedFileURL(id: id)
        let data = try Data(contentsOf: source)
        guard let text = TextFile.decode(data) else {
            throw OmnieDocumentError.notUTF8(name: locked.name)
        }
        let name = OmnieFileName.uniqued(locked.name, existing: try occupiedNames().subtracting([locked.name]))
        let created = try writeNew(id: locked.id, name: name, contents: text, now: locked.modifiedAt)
        try fileManager.removeItem(at: source)
        try removeLocked(id: id)
        return created
    }

    public func applyBackupPolicy() throws {
        try applyExclusion(to: sharedRoot)
        try applyExclusion(to: privateRoot)
        if fileManager.fileExists(atPath: catalog.documentsDirectory.path) {
            try applyExclusion(to: catalog.documentsDirectory)
        }
        if fileManager.fileExists(atPath: catalog.catalogFileURL.path) {
            try applyExclusion(to: catalog.catalogFileURL)
        }
    }

    public func sharedCatalog() throws -> OmnieCatalog {
        try catalog.loadCatalog(fileManager: fileManager)
    }

    /// A temporary copy with the display name, for the share sheet.
    public func exportURL(id: String) throws -> URL {
        guard let document = try documents().first(where: { $0.id == id }) else {
            throw OmnieDocumentError.documentNotFound(id: id)
        }
        let text = try read(id: id)
        let url = fileManager.temporaryDirectory.appendingPathComponent(document.name)
        try writeProtected(TextFile.encode(text), to: url)
        return url
    }

    private var lockedManifestURL: URL {
        privateRoot.appendingPathComponent("locked.json", isDirectory: false)
    }

    private var lockedFilesDirectory: URL {
        privateRoot.appendingPathComponent("files", isDirectory: true)
    }

    private func lockedFileURL(id: String) -> URL {
        lockedFilesDirectory.appendingPathComponent(id, isDirectory: false)
    }

    private func writeNew(id: String, name: String, contents: String, now: Date) throws -> LibraryDocument {
        let data = TextFile.encode(contents)
        let url = try catalog.fileURL(relativePath: name)
        try writeProtected(data, to: url)
        let facts = try fileFacts(url, fallbackBytes: Int64(data.count), now: now)
        let parts = OmnieFileName.splittingExtension(name)
        let summary = OmnieDocumentSummary(
            id: id,
            name: name,
            fileExtension: parts.ext.lowercased(),
            relativePath: name,
            byteCount: facts.bytes,
            modifiedAt: facts.modified
        )
        var catalogFile = try catalog.loadCatalog(fileManager: fileManager)
        catalogFile.documents.removeAll { $0.id == id }
        catalogFile.documents.append(summary)
        try persist(catalogFile, now: now)
        return library(summary, locked: false)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try DirectorySetup.createProtectedDirectory(directory, fileManager: fileManager)
        try writer.write(data, to: url, protection: .complete)
        try applyExclusion(to: url)
    }

    private func persist(_ catalogFile: OmnieCatalog, now: Date) throws {
        let sorted = OmnieCatalogOrder.sorted(catalogFile.documents)
        let payload = OmnieCatalog(
            contractVersion: OmnieContract.version,
            generatedAt: now,
            documents: sorted
        )
        let data = try OmnieJSON.encoder().encode(payload)
        try writeProtected(data, to: catalog.catalogFileURL)
    }

    private func reconcileCatalog() throws {
        var catalogFile = try catalog.loadCatalog(fileManager: fileManager)
        let known = Set(catalogFile.documents.map(\.relativePath))
        catalogFile.documents.removeAll { summary in
            guard case .success = OmnieFileName.validateRelativePath(summary.relativePath) else {
                return true
            }
            guard let url = try? catalog.fileURL(relativePath: summary.relativePath) else {
                return true
            }
            return !fileManager.fileExists(atPath: url.path)
        }
        let lockedNames = Set(try loadLocked().documents.map(\.name))
        let children = (try? fileManager.contentsOfDirectory(at: catalog.documentsDirectory, includingPropertiesForKeys: nil)) ?? []
        var changed = catalogFile.documents.count != (try catalog.loadCatalog(fileManager: fileManager)).documents.count
        for url in children {
            let name = url.lastPathComponent
            guard !known.contains(name) else { continue }
            guard !lockedNames.contains(name) else { continue }
            guard case .success = OmnieFileName.validateDisplayName(name) else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            let data = (try? Data(contentsOf: url)) ?? Data()
            let facts = try fileFacts(url, fallbackBytes: Int64(data.count), now: Date())
            let parts = OmnieFileName.splittingExtension(name)
            catalogFile.documents.append(
                OmnieDocumentSummary(
                    id: UUID().uuidString.lowercased(),
                    name: name,
                    fileExtension: parts.ext.lowercased(),
                    relativePath: name,
                    byteCount: facts.bytes,
                    modifiedAt: facts.modified
                )
            )
            changed = true
        }
        if changed || !fileManager.fileExists(atPath: catalog.catalogFileURL.path) {
            try persist(catalogFile, now: Date())
        }
    }

    private func sharedSummary(id: String) throws -> OmnieDocumentSummary? {
        try catalog.loadCatalog(fileManager: fileManager).documents.first { $0.id == id }
    }

    private func lockedSummary(id: String) throws -> LockedDocument? {
        try loadLocked().documents.first { $0.id == id }
    }

    private func replaceShared(id: String, with summary: OmnieDocumentSummary) throws {
        var catalogFile = try catalog.loadCatalog(fileManager: fileManager)
        catalogFile.documents.removeAll { $0.id == id }
        catalogFile.documents.append(summary)
        try persist(catalogFile, now: summary.modifiedAt)
    }

    private func removeShared(id: String) throws {
        var catalogFile = try catalog.loadCatalog(fileManager: fileManager)
        catalogFile.documents.removeAll { $0.id == id }
        try persist(catalogFile, now: Date())
    }

    private struct LockedManifest: Codable, Equatable {
        var documents: [LockedDocument]
    }

    private func loadLocked() throws -> LockedManifest {
        guard fileManager.fileExists(atPath: lockedManifestURL.path) else {
            return LockedManifest(documents: [])
        }
        let data = try Data(contentsOf: lockedManifestURL)
        do {
            return try OmnieJSON.decoder().decode(LockedManifest.self, from: data)
        } catch {
            throw OmnieDocumentError.catalogUnreadable
        }
    }

    private func saveLocked(_ manifest: LockedManifest) throws {
        let data = try OmnieJSON.encoder().encode(manifest)
        try writeProtected(data, to: lockedManifestURL)
    }

    private func replaceLocked(id: String, with document: LockedDocument) throws {
        var manifest = try loadLocked()
        manifest.documents.removeAll { $0.id == id }
        manifest.documents.append(document)
        try saveLocked(manifest)
    }

    private func removeLocked(id: String) throws {
        var manifest = try loadLocked()
        manifest.documents.removeAll { $0.id == id }
        try saveLocked(manifest)
    }

    private func occupiedNames() throws -> Set<String> {
        let shared = try catalog.loadCatalog(fileManager: fileManager).documents.map(\.name)
        let locked = try loadLocked().documents.map(\.name)
        return Set(shared + locked)
    }

    private func validatedName(_ name: String) throws -> String {
        switch OmnieFileName.validateDisplayName(name) {
        case let .success(valid):
            return valid
        case let .failure(error):
            throw error
        }
    }

    private func fileFacts(_ url: URL, fallbackBytes: Int64, now: Date) throws -> (modified: Date, bytes: Int64) {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values.contentModificationDate ?? now
        let bytes = Int64(values.fileSize ?? Int(fallbackBytes))
        return (modified, bytes)
    }

    private func applyExclusion(to url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try backup.apply(includeInDeviceBackup: includeInDeviceBackup, to: url)
    }

    private func library(_ summary: OmnieDocumentSummary, locked: Bool) -> LibraryDocument {
        LibraryDocument(
            id: summary.id,
            name: summary.name,
            fileExtension: summary.fileExtension,
            byteCount: summary.byteCount,
            modifiedAt: summary.modifiedAt,
            isLocked: locked
        )
    }
}

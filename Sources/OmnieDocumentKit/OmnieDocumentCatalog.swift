import Foundation

/// Read-only view of the shared Omnie-edit folder.
///
/// ```swift
/// let root = try OmnieContract.requireSharedRoot()
/// let catalog = OmnieDocumentCatalog(rootURL: root)
/// let documents = try catalog.list()
/// let source = try catalog.read(id: documents[0].id)
/// ```
///
/// Layout, relative to the app group container:
///
/// ```
/// OmnieEdit/catalog.json
/// OmnieEdit/Documents/<file name>
/// ```
///
/// `catalog.json` is replaced atomically. `list()` skips entries whose path is
/// unsafe or whose file is gone. An unsupported `contractVersion` throws.
/// Locked documents are not in this folder.
public struct OmnieDocumentCatalog: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public var documentsDirectory: URL {
        rootURL.appendingPathComponent(OmnieContract.documentsDirectoryName, isDirectory: true)
    }

    public var catalogFileURL: URL {
        rootURL.appendingPathComponent(OmnieContract.catalogFileName, isDirectory: false)
    }

    public func list(fileManager: FileManager = .default) throws -> [OmnieDocumentSummary] {
        let catalog = try loadCatalog(fileManager: fileManager)
        let visible = catalog.documents.filter { summary in
            guard case .success = OmnieFileName.validateRelativePath(summary.relativePath) else {
                return false
            }
            guard let url = try? fileURL(relativePath: summary.relativePath) else {
                return false
            }
            return fileManager.fileExists(atPath: url.path)
        }
        return OmnieCatalogOrder.sorted(visible)
    }

    public func read(id: String, fileManager: FileManager = .default) throws -> String {
        let url = try fileURL(id: id, fileManager: fileManager)
        let data = try Data(contentsOf: url)
        guard let text = TextFile.decode(data) else {
            let name = url.lastPathComponent
            throw OmnieDocumentError.notUTF8(name: name)
        }
        return text
    }

    public func fileURL(id: String, fileManager: FileManager = .default) throws -> URL {
        let catalog = try loadCatalog(fileManager: fileManager)
        guard let summary = catalog.documents.first(where: { $0.id == id }) else {
            throw OmnieDocumentError.documentNotFound(id: id)
        }
        let url = try fileURL(relativePath: summary.relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw OmnieDocumentError.fileMissing(name: summary.name)
        }
        return url
    }

    public func loadCatalog(fileManager: FileManager = .default) throws -> OmnieCatalog {
        guard fileManager.fileExists(atPath: catalogFileURL.path) else {
            return OmnieCatalog(contractVersion: OmnieContract.version, generatedAt: Date(timeIntervalSince1970: 0), documents: [])
        }
        let data: Data
        do {
            data = try Data(contentsOf: catalogFileURL)
        } catch {
            throw OmnieDocumentError.catalogUnreadable
        }
        let catalog: OmnieCatalog
        do {
            catalog = try OmnieJSON.decoder().decode(OmnieCatalog.self, from: data)
        } catch {
            throw OmnieDocumentError.catalogUnreadable
        }
        guard catalog.contractVersion == OmnieContract.version else {
            throw OmnieDocumentError.unsupportedContractVersion(
                found: catalog.contractVersion,
                supported: OmnieContract.version
            )
        }
        return catalog
    }

    public func fileURL(relativePath: String) throws -> URL {
        switch OmnieFileName.validateRelativePath(relativePath) {
        case let .failure(error):
            throw error
        case let .success(name):
            let directory = documentsDirectory.standardizedFileURL
            let child = directory.appendingPathComponent(name).standardizedFileURL
            let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
            guard child.path.hasPrefix(prefix) else {
                throw OmnieDocumentError.unsafePath(relativePath)
            }
            return child
        }
    }
}

public enum TextFile {
    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        return String(data: data, encoding: .utf8)
    }

    public static func encode(_ string: String) -> Data {
        Data(string.utf8)
    }
}

import FileProvider
import Foundation
import OmnieDocumentKit

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    required init(domain: NSFileProviderDomain) {
        super.init()
        _ = domain
    }

    func invalidate() {}

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        if identifier == .rootContainer {
            completionHandler(OmnieRootItem(), nil)
            return Progress()
        }
        do {
            let summary = try lookup(identifier.rawValue)
            completionHandler(OmnieFileItem(summary: summary), nil)
        } catch {
            completionHandler(nil, error)
        }
        return Progress()
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        _ = requestedVersion
        _ = request
        guard itemIdentifier != .rootContainer else {
            completionHandler(nil, nil, readOnlyError())
            return Progress()
        }
        do {
            let catalog = try makeCatalog()
            let summary = try lookup(itemIdentifier.rawValue)
            let source = try catalog.fileURL(id: summary.id)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(summary.fileExtension.isEmpty ? "txt" : summary.fileExtension)
            try FileManager.default.copyItem(at: source, to: destination)
            completionHandler(destination, OmnieFileItem(summary: summary), nil)
        } catch {
            completionHandler(nil, nil, error)
        }
        return Progress()
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        _ = (itemTemplate, fields, url, options, request)
        completionHandler(nil, [], false, readOnlyError())
        return Progress()
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        _ = (item, version, changedFields, newContents, options, request)
        completionHandler(nil, [], false, readOnlyError())
        return Progress()
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        _ = (identifier, version, options, request)
        completionHandler(readOnlyError())
        return Progress()
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        _ = request
        if containerItemIdentifier == .rootContainer {
            return OmnieEnumerator(kind: .root)
        }
        if containerItemIdentifier == .workingSet {
            return OmnieEnumerator(kind: .workingSet)
        }
        throw NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.Code.noSuchItem.rawValue
        )
    }

    private func makeCatalog() throws -> OmnieDocumentCatalog {
        OmnieDocumentCatalog(rootURL: try OmnieContract.requireSharedRoot())
    }

    private func lookup(_ id: String) throws -> OmnieDocumentSummary {
        guard let summary = try makeCatalog().list().first(where: { $0.id == id }) else {
            throw NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.noSuchItem.rawValue
            )
        }
        return summary
    }

    private func readOnlyError() -> NSError {
        NSError(
            domain: NSCocoaErrorDomain,
            code: NSFeatureUnsupportedError,
            userInfo: [
                NSLocalizedDescriptionKey: "Edit this file in Omnie-edit. The Files view is read-only.",
            ]
        )
    }
}

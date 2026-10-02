import Foundation

/// On-device contract between Omnie-edit and first-party peers such as omnie-ios.
///
/// Peers read documents. They do not write the catalog or the files. Omnie-edit is
/// the only writer in v1. Locked documents are absent from this container.
public enum OmnieContract {
    /// Bump only for breaking changes. Unknown versions must be rejected.
    /// Additive JSON fields may appear without a bump; decoders ignore unknown keys.
    public static let version = 1

    /// App Group both apps must entitlement. Same Apple Developer team required.
    public static let appGroupIdentifier = "group.app.omnie.edit"

    /// Folder inside the app group container.
    public static let rootFolderName = "OmnieEdit"

    public static let documentsDirectoryName = "Documents"
    public static let catalogFileName = "catalog.json"

    /// File Provider domain Omnie-edit registers. Read-only projection of the catalog.
    public static let fileProviderDomainIdentifier = "app.omnie.edit.documents"
    public static let fileProviderDomainDisplayName = "Omnie-edit"

    /// `…/OmnieEdit` inside the shared app group, or nil when the entitlement is absent.
    public static func sharedRoot(fileManager: FileManager = .default) -> URL? {
        #if os(iOS) || os(macOS) || os(visionOS)
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return container.appendingPathComponent(rootFolderName, isDirectory: true)
        #else
        _ = fileManager
        return nil
        #endif
    }

    public static func requireSharedRoot(fileManager: FileManager = .default) throws -> URL {
        guard let root = sharedRoot(fileManager: fileManager) else {
            throw OmnieDocumentError.appGroupUnavailable
        }
        return root
    }
}

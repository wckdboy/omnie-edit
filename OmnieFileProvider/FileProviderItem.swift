import FileProvider
import Foundation
import OmnieDocumentKit
import UniformTypeIdentifiers

final class OmnieRootItem: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { OmnieContract.fileProviderDomainDisplayName }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: Data([1]), metadataVersion: Data([1]))
    }
}

final class OmnieFileItem: NSObject, NSFileProviderItem {
    private let summary: OmnieDocumentSummary

    init(summary: OmnieDocumentSummary) {
        self.summary = summary
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(summary.id)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { summary.name }
    var contentType: UTType {
        UTType(filenameExtension: summary.fileExtension) ?? .plainText
    }
    var documentSize: NSNumber? { NSNumber(value: summary.byteCount) }
    var contentModificationDate: Date? { summary.modifiedAt }
    var capabilities: NSFileProviderItemCapabilities { [.allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let token = "\(summary.modifiedAt.timeIntervalSince1970)-\(summary.byteCount)"
        let data = Data(token.utf8)
        return NSFileProviderItemVersion(contentVersion: data, metadataVersion: data)
    }
}

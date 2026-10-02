import FileProvider
import Foundation
import OmnieDocumentKit

final class OmnieEnumerator: NSObject, NSFileProviderEnumerator {
    enum Kind {
        case root
        case workingSet
    }

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        switch kind {
        case .workingSet:
            observer.finishEnumerating(upTo: nil)
        case .root:
            do {
                let root = try OmnieContract.requireSharedRoot()
                let items: [any NSFileProviderItemProtocol] = try OmnieDocumentCatalog(rootURL: root).list().map { summary in
                    OmnieFileItem(summary: summary)
                }
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        do {
            let root = try OmnieContract.requireSharedRoot()
            let catalog = try OmnieDocumentCatalog(rootURL: root).loadCatalog()
            let stamp = formatter.string(from: catalog.generatedAt)
            let data = stamp.data(using: .utf8) ?? Data([0])
            completionHandler(NSFileProviderSyncAnchor(data))
        } catch {
            completionHandler(NSFileProviderSyncAnchor(Data([0])))
        }
    }
}

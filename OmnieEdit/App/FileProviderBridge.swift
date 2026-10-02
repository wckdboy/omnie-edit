import FileProvider
import Foundation
import OmnieDocumentKit

/// Registers a read-only File Provider domain and tells it when the catalog changes.
enum FileProviderBridge {
    private static var domain: NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(OmnieContract.fileProviderDomainIdentifier),
            displayName: OmnieContract.fileProviderDomainDisplayName
        )
    }

    static func registerIfNeeded() {
        NSFileProviderManager.getDomains { domains, _ in
            let identifier = domain.identifier
            if domains.contains(where: { $0.identifier == identifier }) {
                return
            }
            NSFileProviderManager.add(domain, completionHandler: nil)
        }
    }

    static func signalChanges() {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: .rootContainer) { _ in }
    }
}

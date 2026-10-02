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
        // The iOS 27 SDK exposes the domain list only as the async `domains()`.
        let domain = self.domain
        Task {
            let existing = (try? await NSFileProviderManager.domains()) ?? []
            if existing.contains(where: { $0.identifier == domain.identifier }) {
                return
            }
            try? await NSFileProviderManager.add(domain)
        }
    }

    static func signalChanges() {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: .rootContainer) { _ in }
    }
}

import Foundation
import Observation
import OmnieDocumentKit
import OmnieEditCore
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum StorageKind: Equatable {
        case shared
        case privateFallback
    }

    private let defaults: UserDefaults
    private let authenticator: Authenticating
    let store: DocumentStore

    private(set) var documents: [LibraryDocument] = []
    private(set) var storageKind: StorageKind
    var settings: EditorSettings {
        didSet { commitSettings() }
    }
    var gate: SessionGate
    var lastError: String?

    init(
        defaults: UserDefaults = .standard,
        authenticator: Authenticating = DeviceAuthenticator(),
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.authenticator = authenticator
        let location = StorageLocation.resolve(fileManager: fileManager)
        let loaded = EditorSettingsStore.load(from: defaults)
        settings = loaded
        storageKind = location.kind
        store = DocumentStore(
            sharedRoot: location.sharedRoot,
            privateRoot: location.privateRoot,
            includeInDeviceBackup: loaded.includeInDeviceBackup
        )
        gate = SessionGate.coldStart(appLockEnabled: loaded.appLockEnabled)
        do {
            try store.prepare()
            documents = try store.documents()
        } catch {
            lastError = error.localizedDescription
        }
        FileProviderBridge.registerIfNeeded()
    }

    var storageSummary: String {
        switch storageKind {
        case .shared:
            return "Shared with Omnie apps on this iPhone."
        case .privateFallback:
            return "Private to Omnie-edit. The app group is not available in this build, so omnie-ios cannot read these files yet."
        }
    }

    func reload() {
        do {
            documents = try store.documents()
            FileProviderBridge.signalChanges()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func create(name: String) -> LibraryDocument? {
        do {
            let document = try store.create(name: name, contents: "")
            reload()
            return document
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func importFile(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            _ = try store.importData(data, preferredName: url.lastPathComponent)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rename(id: String, to name: String) {
        do {
            _ = try store.rename(id: id, to: name)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(id: String) {
        do {
            try store.delete(id: id)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func lockDocument(id: String) {
        do {
            try store.lock(id: id)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unlockDocument(id: String) async -> Bool {
        let ok = await authenticator.authenticate(reason: "Unlock this file")
        guard ok else { return false }
        do {
            _ = try store.unlock(id: id)
            gate = gate.grantingDocumentUnlock(id: id)
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func authorizeOpen(of document: LibraryDocument) async -> Bool {
        guard gate.needsDocumentUnlock(id: document.id, isLocked: document.isLocked) else {
            return true
        }
        let ok = await authenticator.authenticate(reason: "Unlock \(document.name)")
        guard ok else { return false }
        gate = gate.grantingDocumentUnlock(id: document.id)
        return true
    }

    func unlockApp() async {
        guard gate.needsAppUnlock else { return }
        let ok = await authenticator.authenticate(reason: "Unlock Omnie-edit")
        if ok {
            gate = gate.grantingAppUnlock()
        }
    }

    func setAppLockEnabled(_ enabled: Bool) async {
        if enabled {
            let ok = await authenticator.authenticate(reason: "Turn on the Omnie-edit lock")
            guard ok else {
                lastError = "Face ID or a device passcode is required to lock Omnie-edit."
                return
            }
            settings.appLockEnabled = true
            gate.appLockEnabled = true
            gate = gate.grantingAppUnlock()
        } else {
            settings.appLockEnabled = false
            gate.appLockEnabled = false
            gate.appUnlocked = true
            gate.privacyCover = false
        }
    }

    func handle(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            NotificationCenter.default.post(name: .omnieFlushSaves, object: nil)
            gate = gate.transition(.active, shieldOnInactive: hasLockedDocuments)
            reload()
        case .inactive:
            NotificationCenter.default.post(name: .omnieFlushSaves, object: nil)
            gate = gate.transition(.inactive, shieldOnInactive: hasLockedDocuments)
        case .background:
            NotificationCenter.default.post(name: .omnieFlushSaves, object: nil)
            gate = gate.transition(.background, shieldOnInactive: hasLockedDocuments)
        @unknown default:
            break
        }
    }

    func makeEditor(id: String) -> EditorModel? {
        do {
            return try EditorModel(documentID: id, store: store) { [weak self] in
                self?.reload()
            }
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private var hasLockedDocuments: Bool {
        documents.contains(where: \.isLocked)
    }

    private func commitSettings() {
        let clamped = settings.clamped()
        if clamped != settings {
            settings = clamped
            return
        }
        EditorSettingsStore.save(settings, to: defaults)
        store.includeInDeviceBackup = settings.includeInDeviceBackup
        do {
            try store.applyBackupPolicy()
        } catch {
            lastError = error.localizedDescription
        }
        gate.appLockEnabled = settings.appLockEnabled
    }
}

enum StorageLocation {
    static func resolve(fileManager: FileManager = .default) -> (
        sharedRoot: URL,
        privateRoot: URL,
        kind: AppModel.StorageKind
    ) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let privateRoot = base.appendingPathComponent("OmnieEditPrivate", isDirectory: true)
        if let shared = OmnieContract.sharedRoot(fileManager: fileManager) {
            return (shared, privateRoot, .shared)
        }
        let fallback = base.appendingPathComponent("OmnieEdit", isDirectory: true)
        return (fallback, privateRoot, .privateFallback)
    }
}

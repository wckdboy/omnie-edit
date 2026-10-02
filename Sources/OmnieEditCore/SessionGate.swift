import Foundation

public enum SessionPhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

/// When the editor UI must hide documents and when a locked file may be shown.
/// Face ID itself lives in the app. This type only records the decision.
public struct SessionGate: Equatable, Sendable {
    public var appLockEnabled: Bool
    public var appUnlocked: Bool
    public var privacyCover: Bool
    public var unlockedDocumentIDs: Set<String>

    public init(
        appLockEnabled: Bool,
        appUnlocked: Bool,
        privacyCover: Bool,
        unlockedDocumentIDs: Set<String>
    ) {
        self.appLockEnabled = appLockEnabled
        self.appUnlocked = appUnlocked
        self.privacyCover = privacyCover
        self.unlockedDocumentIDs = unlockedDocumentIDs
    }

    public static func coldStart(appLockEnabled: Bool) -> SessionGate {
        SessionGate(
            appLockEnabled: appLockEnabled,
            appUnlocked: !appLockEnabled,
            privacyCover: appLockEnabled,
            unlockedDocumentIDs: []
        )
    }

    public var needsAppUnlock: Bool {
        appLockEnabled && !appUnlocked
    }

    public func needsDocumentUnlock(id: String, isLocked: Bool) -> Bool {
        isLocked && !unlockedDocumentIDs.contains(id)
    }

    public func grantingAppUnlock() -> SessionGate {
        var copy = self
        copy.appUnlocked = true
        copy.privacyCover = false
        return copy
    }

    public func grantingDocumentUnlock(id: String) -> SessionGate {
        var copy = self
        copy.unlockedDocumentIDs.insert(id)
        return copy
    }

    public func transition(_ phase: SessionPhase, shieldOnInactive: Bool = false) -> SessionGate {
        var copy = self
        switch phase {
        case .active:
            copy.privacyCover = false
        case .inactive:
            if appLockEnabled || shieldOnInactive {
                copy.privacyCover = true
            }
        case .background:
            copy.unlockedDocumentIDs = []
            if appLockEnabled {
                copy.appUnlocked = false
                copy.privacyCover = true
            } else {
                copy.privacyCover = false
            }
        }
        return copy
    }
}

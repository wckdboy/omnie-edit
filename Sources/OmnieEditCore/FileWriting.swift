import Foundation

/// Protection requested for every document write.
/// On iOS this is `NSFileProtectionComplete`: unreadable while the device is locked.
public enum FileProtectionIntent: String, Equatable, Sendable {
    case complete
}

public protocol FileWriting {
    func write(_ data: Data, to url: URL, protection: FileProtectionIntent) throws
}

public struct ProtectedFileWriter: FileWriting {
    public init() {}

    public func write(_ data: Data, to url: URL, protection: FileProtectionIntent) throws {
        switch protection {
        case .complete:
            try writeComplete(data, to: url)
        }
    }

    private func writeComplete(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}

public protocol BackupMarking {
    func apply(includeInDeviceBackup: Bool, to url: URL) throws
}

public enum BackupExclusion {
    public static func isExcluded(includeInDeviceBackup: Bool) -> Bool {
        !includeInDeviceBackup
    }

    public static func apply(includeInDeviceBackup: Bool, to url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = isExcluded(includeInDeviceBackup: includeInDeviceBackup)
        var mutable = url
        try mutable.setResourceValues(values)
    }
}

public struct URLResourceBackupMarker: BackupMarking {
    public init() {}

    public func apply(includeInDeviceBackup: Bool, to url: URL) throws {
        try BackupExclusion.apply(includeInDeviceBackup: includeInDeviceBackup, to: url)
    }
}

enum DirectorySetup {
    static func createProtectedDirectory(_ url: URL, fileManager: FileManager) throws {
        #if os(iOS)
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        #else
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        #endif
    }
}

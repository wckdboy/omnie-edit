import Foundation
import OmnieDocumentKit

public enum AppTheme: String, Codable, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark
    case monochrome
}

public enum SuggestedExtensions {
    public static let all = [
        "txt", "md", "swift", "py", "js", "ts", "json", "html", "css", "sh",
        "go", "rs", "c", "cpp", "h", "yaml", "yml", "sql", "rb", "xml", "toml", "log",
    ]
    public static let fallback = "txt"

    public static func normalized(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let allowed = cleaned.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        guard allowed, (1...8).contains(cleaned.count) else {
            return fallback
        }
        return cleaned
    }
}

public struct EditorSettings: Equatable, Sendable {
    public var theme: AppTheme
    public var fontSize: Double
    public var useMonospace: Bool
    public var showLineNumbers: Bool
    public var softWrap: Bool
    public var defaultExtension: String
    public var appLockEnabled: Bool
    /// When false, document roots are marked excluded from device backup.
    public var includeInDeviceBackup: Bool

    public static let minFontSize = 12.0
    public static let maxFontSize = 28.0

    public static let `default` = EditorSettings(
        theme: .system,
        fontSize: 16,
        useMonospace: true,
        showLineNumbers: true,
        softWrap: true,
        defaultExtension: SuggestedExtensions.fallback,
        appLockEnabled: false,
        includeInDeviceBackup: false
    )

    public init(
        theme: AppTheme,
        fontSize: Double,
        useMonospace: Bool,
        showLineNumbers: Bool,
        softWrap: Bool,
        defaultExtension: String,
        appLockEnabled: Bool,
        includeInDeviceBackup: Bool
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.useMonospace = useMonospace
        self.showLineNumbers = showLineNumbers
        self.softWrap = softWrap
        self.defaultExtension = defaultExtension
        self.appLockEnabled = appLockEnabled
        self.includeInDeviceBackup = includeInDeviceBackup
    }

    public func clamped() -> EditorSettings {
        var copy = self
        copy.fontSize = min(Self.maxFontSize, max(Self.minFontSize, fontSize))
        copy.defaultExtension = SuggestedExtensions.normalized(defaultExtension)
        return copy
    }
}

extension EditorSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case theme
        case fontSize
        case useMonospace
        case showLineNumbers
        case softWrap
        case defaultExtension
        case appLockEnabled
        case includeInDeviceBackup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let themeRaw = try container.decodeIfPresent(String.self, forKey: .theme) ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        let fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.default.fontSize
        let useMonospace = try container.decodeIfPresent(Bool.self, forKey: .useMonospace) ?? true
        let showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
        let softWrap = try container.decodeIfPresent(Bool.self, forKey: .softWrap) ?? true
        let defaultExtension = try container.decodeIfPresent(String.self, forKey: .defaultExtension) ?? SuggestedExtensions.fallback
        let appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        let includeInDeviceBackup = try container.decodeIfPresent(Bool.self, forKey: .includeInDeviceBackup) ?? false
        self.init(
            theme: theme,
            fontSize: fontSize,
            useMonospace: useMonospace,
            showLineNumbers: showLineNumbers,
            softWrap: softWrap,
            defaultExtension: defaultExtension,
            appLockEnabled: appLockEnabled,
            includeInDeviceBackup: includeInDeviceBackup
        )
        self = clamped()
    }

    public func encode(to encoder: Encoder) throws {
        let clamped = clamped()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clamped.theme.rawValue, forKey: .theme)
        try container.encode(clamped.fontSize, forKey: .fontSize)
        try container.encode(clamped.useMonospace, forKey: .useMonospace)
        try container.encode(clamped.showLineNumbers, forKey: .showLineNumbers)
        try container.encode(clamped.softWrap, forKey: .softWrap)
        try container.encode(clamped.defaultExtension, forKey: .defaultExtension)
        try container.encode(clamped.appLockEnabled, forKey: .appLockEnabled)
        try container.encode(clamped.includeInDeviceBackup, forKey: .includeInDeviceBackup)
    }
}

public enum EditorSettingsStore {
    public static let storageKey = "omnie.editor.settings.v1"

    public static func load(from defaults: UserDefaults) -> EditorSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return .default
        }
        guard let settings = try? OmnieJSON.decoder().decode(EditorSettings.self, from: data) else {
            return .default
        }
        return settings.clamped()
    }

    public static func save(_ settings: EditorSettings, to defaults: UserDefaults) {
        let clamped = settings.clamped()
        guard let data = try? OmnieJSON.encoder().encode(clamped) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

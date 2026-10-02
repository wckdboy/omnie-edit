import Foundation

public enum OmnieFileName {
    public static let maxUTF8Bytes = 255

    public static func validateDisplayName(_ raw: String) -> Result<String, OmnieDocumentError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.nameRejected(raw))
        }
        guard trimmed != ".", trimmed != ".." else {
            return .failure(.nameRejected(trimmed))
        }
        guard !trimmed.hasPrefix(".") else {
            return .failure(.nameRejected(trimmed))
        }
        guard !trimmed.hasSuffix("."), !trimmed.hasSuffix(" ") else {
            return .failure(.nameRejected(trimmed))
        }
        if trimmed.unicodeScalars.contains(where: isForbiddenScalar) {
            return .failure(.nameRejected(trimmed))
        }
        guard Data(trimmed.utf8).count <= maxUTF8Bytes else {
            return .failure(.nameRejected(trimmed))
        }
        return .success(trimmed)
    }

    /// A single path component. Directory separators and traversal are rejected.
    public static func validateRelativePath(_ raw: String) -> Result<String, OmnieDocumentError> {
        switch validateDisplayName(raw) {
        case let .success(name):
            return .success(name)
        case .failure:
            return .failure(.unsafePath(raw))
        }
    }

    public static func splittingExtension(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, "")
        }
        let extStart = name.index(after: dot)
        let ext = String(name[extStart...])
        guard !ext.isEmpty else {
            return (name, "")
        }
        return (String(name[..<dot]), ext)
    }

    public static func joining(base: String, ext: String) -> String {
        let cleaned = ext.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleaned.isEmpty else { return base }
        return "\(base).\(cleaned)"
    }

    public static func uniqued(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let parts = splittingExtension(name)
        var index = 2
        while true {
            let candidate = parts.ext.isEmpty
                ? "\(parts.base) \(index)"
                : "\(parts.base) \(index).\(parts.ext)"
            if !existing.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    public static func lastPathComponent(_ preferredName: String) -> String {
        let slashNormalized = preferredName.replacingOccurrences(of: "\\", with: "/")
        return URL(fileURLWithPath: slashNormalized).lastPathComponent
    }

    private static func isForbiddenScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x20 || scalar.value == 0x7F {
            return true
        }
        switch scalar {
        case "/", "\\", ":", "*", "?", "\"", "<", ">", "|":
            return true
        default:
            return false
        }
    }
}

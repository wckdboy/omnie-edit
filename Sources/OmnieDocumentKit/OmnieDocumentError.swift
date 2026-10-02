import Foundation

public enum OmnieDocumentError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case unsupportedContractVersion(found: Int, supported: Int)
    case catalogUnreadable
    case documentNotFound(id: String)
    case unsafePath(String)
    case nameRejected(String)
    case alreadyExists(String)
    case notUTF8(name: String)
    case fileMissing(name: String)
}

extension OmnieDocumentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The Omnie-edit shared folder is not available."
        case let .unsupportedContractVersion(found, supported):
            return "Catalog version \(found) is not supported (expected \(supported))."
        case .catalogUnreadable:
            return "The document catalog could not be read."
        case let .documentNotFound(id):
            return "No shared document with id \(id)."
        case let .unsafePath(path):
            return "Rejected path \(path)."
        case let .nameRejected(name):
            return "Rejected file name \(name)."
        case let .alreadyExists(name):
            return "A file named \(name) already exists."
        case let .notUTF8(name):
            return "\(name) is not UTF-8 text."
        case let .fileMissing(name):
            return "\(name) is missing from disk."
        }
    }
}

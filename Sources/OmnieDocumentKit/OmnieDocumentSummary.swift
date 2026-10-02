import Foundation

public struct OmnieDocumentSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Lowercase extension without the dot. Empty when the file has none.
    public var fileExtension: String
    /// Single path component inside the documents directory. v1 is flat.
    public var relativePath: String
    public var byteCount: Int64
    public var modifiedAt: Date

    public init(
        id: String,
        name: String,
        fileExtension: String,
        relativePath: String,
        byteCount: Int64,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileExtension = "extension"
        case relativePath
        case byteCount
        case modifiedAt
    }
}

public struct OmnieCatalog: Codable, Equatable, Sendable {
    public var contractVersion: Int
    public var generatedAt: Date
    public var documents: [OmnieDocumentSummary]

    public init(contractVersion: Int, generatedAt: Date, documents: [OmnieDocumentSummary]) {
        self.contractVersion = contractVersion
        self.generatedAt = generatedAt
        self.documents = documents
    }
}

public enum OmnieCatalogOrder {
    /// Newest first. Name, then id, breaks ties. Peers should use this order.
    public static func sorted(_ documents: [OmnieDocumentSummary]) -> [OmnieDocumentSummary] {
        documents.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }
}

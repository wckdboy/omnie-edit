import Foundation

public enum TextSearch {
    public struct Match: Equatable, Sendable {
        public var utf16Location: Int
        public var utf16Length: Int

        public init(utf16Location: Int, utf16Length: Int) {
            self.utf16Location = utf16Location
            self.utf16Length = utf16Length
        }
    }

    public static func matches(in text: String, query: String, caseInsensitive: Bool) -> [Match] {
        guard !query.isEmpty else { return [] }
        var options: String.CompareOptions = [.literal]
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }
        var found: [Match] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            guard let range = text.range(of: query, options: options, range: searchStart..<text.endIndex) else {
                break
            }
            let location = range.lowerBound.utf16Offset(in: text)
            let end = range.upperBound.utf16Offset(in: text)
            let length = end - location
            found.append(Match(utf16Location: location, utf16Length: length))
            if range.lowerBound == range.upperBound {
                searchStart = text.index(after: range.lowerBound)
            } else {
                searchStart = range.upperBound
            }
        }
        return found
    }

    public static func wrappedIndex(current: Int, count: Int, step: Int) -> Int {
        guard count > 0 else { return 0 }
        let modulus = ((current + step) % count + count) % count
        return modulus
    }
}

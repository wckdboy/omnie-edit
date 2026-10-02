import Foundation

public enum SyntaxKind: String, Equatable, Sendable {
    case keyword
    case string
    case comment
    case number
    case heading
    case tag
}

public struct SyntaxToken: Equatable, Sendable {
    public var utf16Offset: Int
    public var utf16Length: Int
    public var kind: SyntaxKind

    public init(utf16Offset: Int, utf16Length: Int, kind: SyntaxKind) {
        self.utf16Offset = utf16Offset
        self.utf16Length = utf16Length
        self.kind = kind
    }
}

public enum SyntaxHighlighter {
    /// Files larger than this are left plain so typing stays responsive.
    public static let maximumUTF16Units = 200_000

    public static func tokens(in text: String, language: SourceLanguage) -> [SyntaxToken] {
        if text.utf16.count > maximumUTF16Units {
            return []
        }
        switch language {
        case .plain:
            return []
        case .markdown:
            return markdownTokens(in: text)
        case .swift, .python, .javascript, .typescript, .json, .html, .css, .shell, .go, .rust, .c, .cpp, .ruby, .yaml, .sql, .toml:
            guard let rules = LanguageRules.rules(for: language) else {
                return []
            }
            return scan(text, rules: rules)
        }
    }

    private static func markdownTokens(in text: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var offset = 0
        var inFence = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let lineText = String(line)
            let width = utf16Count(lineText)
            if lineText.hasPrefix("```") {
                tokens.append(SyntaxToken(utf16Offset: offset, utf16Length: width, kind: .comment))
                inFence.toggle()
            } else if inFence {
                tokens.append(SyntaxToken(utf16Offset: offset, utf16Length: width, kind: .string))
            } else if lineText.hasPrefix("#") {
                tokens.append(SyntaxToken(utf16Offset: offset, utf16Length: width, kind: .heading))
            }
            offset += width + 1
        }
        return tokens.filter { $0.utf16Length > 0 }
    }

    private static func scan(_ text: String, rules: LanguageRules) -> [SyntaxToken] {
        let characters = Array(text)
        let widths = characters.map(utf16Count)
        var tokens: [SyntaxToken] = []
        var index = 0
        var offset = 0
        var blockDepth = 0

        func emit(_ kind: SyntaxKind, from start: Int, length: Int) {
            guard length > 0 else { return }
            tokens.append(SyntaxToken(utf16Offset: start, utf16Length: length, kind: kind))
        }

        while index < characters.count {
            if blockDepth > 0, let block = rules.blockComment {
                let start = offset
                var length = 0
                while index < characters.count, !match(block.end, at: index, in: characters) {
                    length += widths[index]
                    index += 1
                }
                emit(.comment, from: start, length: length)
                if match(block.end, at: index, in: characters) {
                    let endWidth = utf16Width(of: block.end, widths: widths, at: index)
                    emit(.comment, from: offset + length, length: endWidth)
                    index += block.end.count
                    offset += length + endWidth
                    blockDepth = 0
                } else {
                    offset += length
                }
                continue
            }

            let character = characters[index]
            if rules.allowsTripleQuote, isTripleQuote(character, at: index, in: characters) {
                let (next, nextOffset) = consumeString(
                    from: index,
                    offset: offset,
                    characters: characters,
                    widths: widths,
                    delimiter: String(repeating: character, count: 3)
                )
                emit(.string, from: offset, length: nextOffset - offset)
                index = next
                offset = nextOffset
                continue
            }

            if rules.quoteCharacters.contains(character) {
                let (next, nextOffset) = consumeString(
                    from: index,
                    offset: offset,
                    characters: characters,
                    widths: widths,
                    delimiter: String(character)
                )
                emit(.string, from: offset, length: nextOffset - offset)
                index = next
                offset = nextOffset
                continue
            }

            if let block = rules.blockComment, match(block.start, at: index, in: characters) {
                let length = utf16Width(of: block.start, widths: widths, at: index)
                emit(.comment, from: offset, length: length)
                index += block.start.count
                offset += length
                blockDepth = 1
                continue
            }

            if startsLineComment(rules.lineComments, at: index, in: characters) {
                let start = offset
                var length = 0
                while index < characters.count, characters[index] != "\n" {
                    length += widths[index]
                    index += 1
                }
                emit(.comment, from: start, length: length)
                offset = start + length
                continue
            }

            if rules.highlightTags, character == "<", index + 1 < characters.count, characters[index + 1] != " " {
                let start = offset
                var length = widths[index]
                index += 1
                offset += widths[index - 1]
                while index < characters.count, characters[index] != ">" {
                    length += widths[index]
                    offset += widths[index]
                    index += 1
                }
                if index < characters.count, characters[index] == ">" {
                    length += widths[index]
                    offset += widths[index]
                    index += 1
                }
                emit(.tag, from: start, length: length)
                continue
            }

            if isNumberStart(characters, at: index) {
                let start = offset
                var length = 0
                let hex = index + 1 < characters.count
                    && characters[index] == "0"
                    && (characters[index + 1] == "x" || characters[index + 1] == "X")
                if hex {
                    length += widths[index] + widths[index + 1]
                    index += 2
                    while index < characters.count, isHexBody(characters[index]) {
                        length += widths[index]
                        index += 1
                    }
                } else {
                    var seenDot = false
                    while index < characters.count {
                        let current = characters[index]
                        if current == "." {
                            if seenDot { break }
                            seenDot = true
                        } else if !current.isNumber && current != "_" {
                            break
                        }
                        length += widths[index]
                        index += 1
                    }
                }
                emit(.number, from: start, length: length)
                offset = start + length
                continue
            }

            if isIdentifierStart(character) {
                let start = offset
                var length = 0
                var word = ""
                while index < characters.count, isIdentifierBody(characters[index]) {
                    word.append(characters[index])
                    length += widths[index]
                    index += 1
                }
                if isKeyword(word, rules: rules) {
                    emit(.keyword, from: start, length: length)
                }
                offset = start + length
                continue
            }

            offset += widths[index]
            index += 1
        }
        return coalesce(tokens)
    }

    private static func isKeyword(_ word: String, rules: LanguageRules) -> Bool {
        if rules.keywordsCaseInsensitive {
            return rules.keywords.contains(word.lowercased())
        }
        return rules.keywords.contains(word)
    }

    private static func coalesce(_ tokens: [SyntaxToken]) -> [SyntaxToken] {
        var result: [SyntaxToken] = []
        for token in tokens where token.utf16Length > 0 {
            if let last = result.last,
               last.kind == token.kind,
               last.utf16Offset + last.utf16Length == token.utf16Offset {
                result[result.count - 1] = SyntaxToken(
                    utf16Offset: last.utf16Offset,
                    utf16Length: last.utf16Length + token.utf16Length,
                    kind: last.kind
                )
            } else {
                result.append(token)
            }
        }
        return result
    }

    private static func consumeString(
        from index: Int,
        offset: Int,
        characters: [Character],
        widths: [Int],
        delimiter: String
    ) -> (Int, Int) {
        var cursor = index
        var unit = offset
        let delimiterCharacters = Array(delimiter)
        func consumeDelimiter() {
            for _ in delimiterCharacters {
                guard cursor < characters.count else { return }
                unit += widths[cursor]
                cursor += 1
            }
        }
        consumeDelimiter()
        while cursor < characters.count {
            if characters[cursor] == "\n", delimiter.count == 1 {
                break
            }
            if characters[cursor] == "\\" {
                unit += widths[cursor]
                cursor += 1
                if cursor < characters.count {
                    unit += widths[cursor]
                    cursor += 1
                }
                continue
            }
            if match(delimiter, at: cursor, in: characters) {
                consumeDelimiter()
                break
            }
            unit += widths[cursor]
            cursor += 1
        }
        return (cursor, unit)
    }

    private static func match(_ needle: String, at index: Int, in characters: [Character]) -> Bool {
        let needleCharacters = Array(needle)
        guard index + needleCharacters.count <= characters.count else { return false }
        for offset in needleCharacters.indices {
            if characters[index + offset] != needleCharacters[offset] {
                return false
            }
        }
        return true
    }

    private static func startsLineComment(_ markers: [String], at index: Int, in characters: [Character]) -> Bool {
        markers.contains { match($0, at: index, in: characters) }
    }

    private static func isTripleQuote(_ character: Character, at index: Int, in characters: [Character]) -> Bool {
        guard character == "\"" || character == "'" else { return false }
        return match(String(repeating: character, count: 3), at: index, in: characters)
    }

    private static func isNumberStart(_ characters: [Character], at index: Int) -> Bool {
        guard characters[index].isNumber else { return false }
        if index == 0 { return true }
        let previous = characters[index - 1]
        return !isIdentifierBody(previous)
    }

    private static func isHexBody(_ character: Character) -> Bool {
        character.isNumber || character == "_"
            || ("a"..."f").contains(character) || ("A"..."F").contains(character)
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func isIdentifierBody(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func utf16Width(of text: String, widths: [Int], at index: Int) -> Int {
        var total = 0
        let count = Array(text).count
        for offset in 0..<count where index + offset < widths.count {
            total += widths[index + offset]
        }
        return total
    }

    private static func utf16Count(_ character: Character) -> Int {
        character.utf16.count
    }

    private static func utf16Count(_ text: String) -> Int {
        text.utf16.count
    }
}

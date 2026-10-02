import Foundation

public enum SourceLanguage: String, Equatable, Sendable, CaseIterable {
    case plain
    case markdown
    case swift
    case python
    case javascript
    case typescript
    case json
    case html
    case css
    case shell
    case go
    case rust
    case c
    case cpp
    case ruby
    case yaml
    case sql
    case toml

    public static func detect(fileExtension: String) -> SourceLanguage {
        switch fileExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "swift":
            return .swift
        case "py":
            return .python
        case "js", "mjs", "jsx":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "json":
            return .json
        case "html", "htm", "xml":
            return .html
        case "css":
            return .css
        case "sh", "bash", "zsh":
            return .shell
        case "go":
            return .go
        case "rs":
            return .rust
        case "c", "h":
            return .c
        case "cpp", "cc", "cxx", "hpp", "hh":
            return .cpp
        case "rb":
            return .ruby
        case "yaml", "yml":
            return .yaml
        case "sql":
            return .sql
        case "toml":
            return .toml
        case "txt", "log", "":
            return .plain
        default:
            return .plain
        }
    }
}

struct LanguageRules {
    var keywords: Set<String>
    var keywordsCaseInsensitive: Bool
    var lineComments: [String]
    var blockComment: (start: String, end: String)?
    var quoteCharacters: Set<Character>
    var allowsTripleQuote: Bool
    var highlightTags: Bool

    static func rules(for language: SourceLanguage) -> LanguageRules? {
        switch language {
        case .plain, .markdown:
            return nil
        case .swift:
            return cFamily(keywords: swiftKeywords, triple: true)
        case .javascript:
            return cFamily(keywords: javascriptKeywords, triple: false, backticks: true)
        case .typescript:
            return cFamily(keywords: typescriptKeywords, triple: false, backticks: true)
        case .json:
            return LanguageRules(
                keywords: ["true", "false", "null"],
                keywordsCaseInsensitive: false,
                lineComments: [],
                blockComment: nil,
                quoteCharacters: ["\""],
                allowsTripleQuote: false,
                highlightTags: false
            )
        case .python:
            return LanguageRules(
                keywords: pythonKeywords,
                keywordsCaseInsensitive: false,
                lineComments: ["#"],
                blockComment: nil,
                quoteCharacters: ["\"", "'"],
                allowsTripleQuote: true,
                highlightTags: false
            )
        case .shell:
            return LanguageRules(
                keywords: shellKeywords,
                keywordsCaseInsensitive: false,
                lineComments: ["#"],
                blockComment: nil,
                quoteCharacters: ["\"", "'", "`"],
                allowsTripleQuote: false,
                highlightTags: false
            )
        case .ruby:
            return LanguageRules(
                keywords: rubyKeywords,
                keywordsCaseInsensitive: false,
                lineComments: ["#"],
                blockComment: nil,
                quoteCharacters: ["\"", "'", "`"],
                allowsTripleQuote: false,
                highlightTags: false
            )
        case .yaml, .toml:
            return LanguageRules(
                keywords: ["true", "false", "null", "yes", "no"],
                keywordsCaseInsensitive: false,
                lineComments: ["#"],
                blockComment: nil,
                quoteCharacters: ["\"", "'"],
                allowsTripleQuote: false,
                highlightTags: false
            )
        case .html:
            return LanguageRules(
                keywords: [],
                keywordsCaseInsensitive: false,
                lineComments: [],
                blockComment: ("<!--", "-->"),
                quoteCharacters: ["\"", "'"],
                allowsTripleQuote: false,
                highlightTags: true
            )
        case .css:
            return cFamily(keywords: [], triple: false).withLineComments([])
        case .go:
            return cFamily(keywords: goKeywords, triple: false, backticks: true)
        case .rust:
            return cFamily(keywords: rustKeywords, triple: false)
        case .c:
            return cFamily(keywords: cKeywords, triple: false)
        case .cpp:
            return cFamily(keywords: cppKeywords, triple: false)
        case .sql:
            return LanguageRules(
                keywords: sqlKeywords,
                keywordsCaseInsensitive: true,
                lineComments: ["--"],
                blockComment: ("/*", "*/"),
                quoteCharacters: ["'", "\""],
                allowsTripleQuote: false,
                highlightTags: false
            )
        }
    }

    private func withLineComments(_ comments: [String]) -> LanguageRules {
        var copy = self
        copy.lineComments = comments
        return copy
    }

    private static func cFamily(
        keywords: Set<String>,
        triple: Bool,
        backticks: Bool = false
    ) -> LanguageRules {
        var quotes: Set<Character> = ["\""]
        if backticks {
            quotes.insert("`")
        }
        return LanguageRules(
            keywords: keywords,
            keywordsCaseInsensitive: false,
            lineComments: ["//"],
            blockComment: ("/*", "*/"),
            quoteCharacters: quotes,
            allowsTripleQuote: triple,
            highlightTags: false
        )
    }
}

private let swiftKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
    "init", "inout", "internal", "let", "operator", "private", "protocol", "public", "rethrows",
    "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default",
    "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
    "switch", "where", "while", "as", "Any", "catch", "false", "is", "nil", "super", "self",
    "Self", "throw", "throws", "true", "try", "async", "await", "some", "any",
]

private let javascriptKeywords: Set<String> = [
    "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
    "do", "else", "export", "extends", "false", "finally", "for", "function", "if", "import",
    "in", "instanceof", "new", "null", "return", "super", "switch", "this", "throw", "true",
    "try", "typeof", "var", "void", "while", "with", "yield", "let", "of", "async", "await",
]

private let typescriptKeywords: Set<String> = javascriptKeywords.union([
    "type", "interface", "implements", "public", "private", "protected", "readonly", "enum",
    "namespace", "abstract", "as", "satisfies", "keyof", "infer",
])

private let pythonKeywords: Set<String> = [
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
    "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
    "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
    "try", "while", "with", "yield",
]

private let goKeywords: Set<String> = [
    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
    "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
    "return", "select", "struct", "switch", "type", "var", "true", "false", "nil",
]

private let rustKeywords: Set<String> = [
    "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
    "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
    "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
    "trait", "true", "type", "unsafe", "use", "where", "while",
]

private let cKeywords: Set<String> = [
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
    "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register",
    "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch",
    "typedef", "union", "unsigned", "void", "volatile", "while",
]

private let cppKeywords: Set<String> = cKeywords.union([
    "class", "namespace", "template", "typename", "public", "private", "protected", "virtual",
    "override", "new", "delete", "this", "throw", "try", "catch", "bool", "true", "false",
    "nullptr", "constexpr", "noexcept", "using",
])

private let rubyKeywords: Set<String> = [
    "BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?",
    "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
    "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then",
    "true", "undef", "unless", "until", "when", "while", "yield",
]

private let shellKeywords: Set<String> = [
    "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do",
    "done", "in", "function", "select", "time", "return", "exit",
]

private let sqlKeywords: Set<String> = [
    "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
    "create", "table", "drop", "alter", "join", "left", "right", "inner", "outer", "on",
    "and", "or", "not", "null", "as", "order", "by", "group", "having", "limit", "offset",
    "distinct", "union", "all", "primary", "key", "foreign", "references", "index",
]

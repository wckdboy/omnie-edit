import XCTest
import OmnieEditCore

final class EditingLogicTests: XCTestCase {
    func testSwiftKeywordsStringsAndComments() {
        let source = """
        let name = "let"
        // let hidden
        /* block
        let still */
        let count = 42
        """
        let tokens = SyntaxHighlighter.tokens(in: source, language: .swift)
        let keywords = words(source, tokens: tokens.filter { $0.kind == .keyword })
        XCTAssertEqual(keywords, ["let", "let"])
        XCTAssertTrue(tokens.contains { $0.kind == .string && slice(source, $0) == "\"let\"" })
        XCTAssertTrue(tokens.contains { $0.kind == .comment && slice(source, $0).contains("hidden") })
        XCTAssertTrue(tokens.contains { $0.kind == .comment && slice(source, $0).contains("still") })
        XCTAssertTrue(tokens.contains { $0.kind == .number && slice(source, $0) == "42" })
    }

    func testStringDoesNotSwallowTrailingCode() {
        let source = "let url = \"http://example.com\"; let done = true"
        let tokens = SyntaxHighlighter.tokens(in: source, language: .swift)
        let keywords = words(source, tokens: tokens.filter { $0.kind == .keyword })
        XCTAssertEqual(keywords, ["let", "let", "true"])
    }

    func testEmojiOffsetUsesUTF16() {
        let source = "🙂 let"
        let keyword = SyntaxHighlighter.tokens(in: source, language: .swift).first { $0.kind == .keyword }
        XCTAssertEqual(keyword?.utf16Offset, 3)
        XCTAssertEqual(keyword?.utf16Length, 3)
    }

    func testMarkdownHeadingAndFence() {
        let source = "# Title\n\n```\nlet x = 1\n```\n"
        let tokens = SyntaxHighlighter.tokens(in: source, language: .markdown)
        XCTAssertEqual(tokens.first?.kind, .heading)
        XCTAssertTrue(tokens.contains { $0.kind == .string && slice(source, $0).contains("let x") })
    }

    func testLanguageDetection() {
        XCTAssertEqual(SourceLanguage.detect(fileExtension: "swift"), .swift)
        XCTAssertEqual(SourceLanguage.detect(fileExtension: "PY"), .python)
        XCTAssertEqual(SourceLanguage.detect(fileExtension: "unknown"), .plain)
        XCTAssertTrue(SyntaxHighlighter.tokens(in: "let a = 1", language: .plain).isEmpty)
    }

    func testOversizedFileStaysPlain() {
        let source = String(repeating: "a", count: SyntaxHighlighter.maximumUTF16Units + 1)
        XCTAssertTrue(SyntaxHighlighter.tokens(in: source, language: .swift).isEmpty)
    }

    func testLiteralSearchWrapsAndSkipsEmptyQuery() {
        let text = "Alpha beta Alpha"
        XCTAssertTrue(TextSearch.matches(in: text, query: "", caseInsensitive: true).isEmpty)
        let matches = TextSearch.matches(in: text, query: "alpha", caseInsensitive: true)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].utf16Location, 0)
        let sensitive = TextSearch.matches(in: text, query: "alpha", caseInsensitive: false)
        XCTAssertTrue(sensitive.isEmpty)
        XCTAssertEqual(TextSearch.wrappedIndex(current: 1, count: 2, step: 1), 0)
        XCTAssertEqual(TextSearch.wrappedIndex(current: 0, count: 2, step: -1), 1)
        XCTAssertEqual(TextSearch.wrappedIndex(current: 0, count: 0, step: 1), 0)
    }

    func testSearchOffsetAfterEmoji() {
        let text = "🙂 Alpha"
        let matches = TextSearch.matches(in: text, query: "Alpha", caseInsensitive: true)
        XCTAssertEqual(matches.first?.utf16Location, 3)
    }

    private func slice(_ text: String, _ token: SyntaxToken) -> String {
        let utf16 = Array(text.utf16)
        let end = token.utf16Offset + token.utf16Length
        guard token.utf16Offset >= 0, end <= utf16.count else { return "" }
        return String(decoding: utf16[token.utf16Offset..<end], as: UTF16.self)
    }

    private func words(_ text: String, tokens: [SyntaxToken]) -> [String] {
        tokens.map { slice(text, $0) }
    }
}

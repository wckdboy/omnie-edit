#if os(iOS)
import Runestone
import SwiftUI
import TreeSitterBashRunestone
import TreeSitterCSSRunestone
import TreeSitterHTMLRunestone
import TreeSitterJavaScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterMarkdownRunestone
import TreeSitterPythonRunestone
import TreeSitterSwiftRunestone
import TreeSitterTOMLRunestone
import TreeSitterTypeScriptRunestone
import TreeSitterYAMLRunestone

/// Commands that SwiftUI can send to the underlying editor without exposing
/// Runestone types to the app target.
public enum CodeEditorCommand: Equatable, Sendable {
    case find(UUID)
    case goToLine(Int, UUID)
    case undo(UUID)
    case redo(UUID)
}

/// Colors the editor renders with. The app resolves this from its own theme
/// (light/dark/monochrome) and hands over plain `UIColor`s so this file stays
/// the only place that has to know about Runestone's `Theme` protocol.
public struct EditorColorTheme: Equatable {
    public var background: UIColor
    public var text: UIColor
    public var gutterBackground: UIColor
    public var secondary: UIColor
    public var hairline: UIColor
    public var keyword: UIColor
    public var string: UIColor
    public var comment: UIColor
    public var number: UIColor
    public var matchBackground: UIColor
    public var currentMatchBackground: UIColor
    public var keywordBold: Bool

    public init(
        background: UIColor,
        text: UIColor,
        gutterBackground: UIColor,
        secondary: UIColor,
        hairline: UIColor,
        keyword: UIColor,
        string: UIColor,
        comment: UIColor,
        number: UIColor,
        matchBackground: UIColor,
        currentMatchBackground: UIColor,
        keywordBold: Bool
    ) {
        self.background = background
        self.text = text
        self.gutterBackground = gutterBackground
        self.secondary = secondary
        self.hairline = hairline
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.matchBackground = matchBackground
        self.currentMatchBackground = currentMatchBackground
        self.keywordBold = keywordBold
    }

    /// Runestone's generic built-in colors, used only until the app supplies its own theme.
    public static let `default` = EditorColorTheme(
        background: .white,
        text: DefaultTheme().textColor,
        gutterBackground: DefaultTheme().gutterBackgroundColor,
        secondary: DefaultTheme().lineNumberColor,
        hairline: DefaultTheme().gutterHairlineColor,
        keyword: DefaultTheme().textColor(for: "keyword") ?? DefaultTheme().textColor,
        string: DefaultTheme().textColor(for: "string") ?? DefaultTheme().textColor,
        comment: DefaultTheme().textColor(for: "comment") ?? DefaultTheme().textColor,
        number: DefaultTheme().textColor(for: "number") ?? DefaultTheme().textColor,
        matchBackground: .systemYellow.withAlphaComponent(0.2),
        currentMatchBackground: .systemYellow,
        keywordBold: false
    )
}

private struct AutoClosingPair: CharacterPair {
    let leading: String
    let trailing: String
}

private let autoClosingCharacterPairs: [CharacterPair] = [
    AutoClosingPair(leading: "(", trailing: ")"),
    AutoClosingPair(leading: "[", trailing: "]"),
    AutoClosingPair(leading: "{", trailing: "}"),
    AutoClosingPair(leading: "\"", trailing: "\""),
    AutoClosingPair(leading: "'", trailing: "'"),
]

/// SwiftUI adapter for Runestone's purpose-built code editor.
///
/// This is the only file in Omnie Edit that knows about Runestone. Keeping the
/// dependency behind this boundary makes upgrades and licensing review simple.
public struct RunestoneCodeEditor: UIViewRepresentable {
    @Binding private var text: String
    private let language: EditorLanguage
    private let showLineNumbers: Bool
    private let softWrap: Bool
    private let fontSize: Double
    private let colorTheme: EditorColorTheme
    private let command: CodeEditorCommand?

    public init(
        text: Binding<String>,
        language: EditorLanguage,
        showLineNumbers: Bool,
        softWrap: Bool,
        fontSize: Double,
        colorTheme: EditorColorTheme = .default,
        command: CodeEditorCommand? = nil
    ) {
        _text = text
        self.language = language
        self.showLineNumbers = showLineNumbers
        self.softWrap = softWrap
        self.fontSize = fontSize
        self.colorTheme = colorTheme
        self.command = command
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        textView.showLineNumbers = showLineNumbers
        textView.gutterMinimumCharacterCount = 1
        textView.gutterLeadingPadding = 4
        textView.gutterTrailingPadding = 6
        textView.isLineWrappingEnabled = softWrap
        textView.lineHeightMultiplier = 1.2
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 8, bottom: 24, right: 8)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.spellCheckingType = .no
        textView.isFindInteractionEnabled = true
        textView.indentStrategy = .space(length: 2)
        textView.characterPairs = autoClosingCharacterPairs
        textView.lineSelectionDisplayType = .line
        textView.backgroundColor = colorTheme.background
        applyState(to: textView)
        return textView
    }

    public func updateUIView(_ textView: TextView, context: Context) {
        context.coordinator.text = $text
        textView.showLineNumbers = showLineNumbers
        textView.isLineWrappingEnabled = softWrap
        textView.backgroundColor = colorTheme.background
        textView.theme = EditorTheme(fontSize: CGFloat(fontSize), colorTheme: colorTheme)

        if textView.text != text {
            applyState(to: textView)
        }
        if context.coordinator.lastCommand != command {
            context.coordinator.lastCommand = command
            perform(command, in: textView)
        }
    }

    private func applyState(to textView: TextView) {
        let theme = EditorTheme(fontSize: CGFloat(fontSize), colorTheme: colorTheme)
        let state: TextViewState
        if let treeSitterLanguage {
            state = TextViewState(
                text: text,
                theme: theme,
                language: treeSitterLanguage
            )
        } else {
            state = TextViewState(
                text: text,
                theme: theme
            )
        }
        textView.setState(state)
    }

    private func perform(_ command: CodeEditorCommand?, in textView: TextView) {
        switch command {
        case .find:
            textView.findInteraction?.presentFindNavigator(showingReplace: false)
        case let .goToLine(line, _):
            _ = textView.goToLine(max(0, line - 1))
        case .undo:
            textView.undoManager?.undo()
        case .redo:
            textView.undoManager?.redo()
        case nil:
            break
        }
    }

    private var treeSitterLanguage: TreeSitterLanguage? {
        switch language {
        case .plain: nil
        case .markdown: .markdown
        case .json: .json
        case .swift: .swift
        case .python: .python
        case .javaScript: .javaScript
        case .typeScript: .typeScript
        case .html: .html
        case .css: .css
        case .shell: .bash
        case .yaml: .yaml
        case .toml: .toml
        }
    }

    public final class Coordinator: NSObject, TextViewDelegate {
        var text: Binding<String>
        var lastCommand: CodeEditorCommand?

        init(text: Binding<String>) {
            self.text = text
        }

        public func textViewDidChange(_ textView: TextView) {
            guard text.wrappedValue != textView.text else { return }
            text.wrappedValue = textView.text
        }
    }
}

/// A theme adapter that renders Runestone's highlight captures using the
/// app's own light/dark/monochrome palette, sized for the user's font setting.
private final class EditorTheme: Theme {
    private let colorTheme: EditorColorTheme
    let font: UIFont
    let lineNumberFont: UIFont

    init(fontSize: CGFloat, colorTheme: EditorColorTheme) {
        self.colorTheme = colorTheme
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        lineNumberFont = .monospacedSystemFont(ofSize: max(10, fontSize - 2), weight: .regular)
    }

    var textColor: UIColor { colorTheme.text }
    var gutterBackgroundColor: UIColor { colorTheme.gutterBackground }
    var gutterHairlineColor: UIColor { colorTheme.hairline }
    var lineNumberColor: UIColor { colorTheme.secondary }
    var selectedLineBackgroundColor: UIColor { colorTheme.text.withAlphaComponent(0.06) }
    var selectedLinesLineNumberColor: UIColor { colorTheme.text }
    var selectedLinesGutterBackgroundColor: UIColor { colorTheme.gutterBackground }
    var invisibleCharactersColor: UIColor { colorTheme.secondary }
    var pageGuideHairlineColor: UIColor { colorTheme.hairline }
    var pageGuideBackgroundColor: UIColor { colorTheme.gutterBackground }
    var markedTextBackgroundColor: UIColor { colorTheme.currentMatchBackground.withAlphaComponent(0.3) }

    func textColor(for highlightName: String) -> UIColor? {
        guard let highlightName = HighlightName(highlightName) else { return nil }
        switch highlightName {
        case .comment:
            return colorTheme.comment
        case .string, .constantCharacter:
            return colorTheme.string
        case .number, .constantBuiltin:
            return colorTheme.number
        case .keyword, .constructor, .variableBuiltin, .type:
            return colorTheme.keyword
        case .function, .property, .variable, .operator, .punctuation:
            return nil
        }
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        guard colorTheme.keywordBold, let highlightName = HighlightName(highlightName) else { return [] }
        switch highlightName {
        case .keyword, .constructor, .type:
            return .bold
        default:
            return []
        }
    }

    @available(iOS 16, *)
    func highlightedRange(forFoundTextRange foundTextRange: NSRange, ofStyle style: UITextSearchFoundTextStyle) -> HighlightedRange? {
        switch style {
        case .found:
            return HighlightedRange(range: foundTextRange, color: colorTheme.matchBackground, cornerRadius: 2)
        case .highlighted:
            return HighlightedRange(range: foundTextRange, color: colorTheme.currentMatchBackground, cornerRadius: 2)
        case .normal:
            return nil
        @unknown default:
            return nil
        }
    }
}

/// `HighlightName` mirrors Runestone's internal capture-name enum (not exported publicly),
/// so highlight-specific coloring can live here without reaching into Runestone internals.
private enum HighlightName: String {
    case comment
    case constantBuiltin = "constant.builtin"
    case constantCharacter = "constant.character"
    case constructor
    case function
    case keyword
    case number
    case `operator`
    case property
    case punctuation
    case string
    case type
    case variable
    case variableBuiltin = "variable.builtin"

    init?(_ rawHighlightName: String) {
        var comps = rawHighlightName.split(separator: ".")
        while !comps.isEmpty {
            let candidate = comps.joined(separator: ".")
            if let match = Self(rawValue: candidate) {
                self = match
                return
            }
            comps.removeLast()
        }
        return nil
    }
}
#endif

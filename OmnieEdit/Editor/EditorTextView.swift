import SwiftUI
import UIKit

struct EditorTextView: UIViewRepresentable {
    var text: String
    var tokens: [SyntaxToken]
    var matches: [TextSearch.Match]
    var currentMatch: Int?
    var selectionNonce: Int
    var fontSize: CGFloat
    var monospace: Bool
    var showLineNumbers: Bool
    var softWrap: Bool
    var palette: Palette
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> CodeEditorView {
        let view = CodeEditorView()
        view.textView.delegate = context.coordinator
        context.coordinator.editor = view
        view.textView.text = text
        apply(to: view, context: context, forceSelection: true)
        return view
    }

    func updateUIView(_ view: CodeEditorView, context: Context) {
        context.coordinator.onChange = onChange
        if view.textView.text != text {
            let selected = view.textView.selectedRange
            view.textView.text = text
            let length = (text as NSString).length
            view.textView.selectedRange = NSRange(
                location: min(selected.location, length),
                length: 0
            )
        }
        let forceSelection = context.coordinator.selectionNonce != selectionNonce
        context.coordinator.selectionNonce = selectionNonce
        apply(to: view, context: context, forceSelection: forceSelection)
    }

    private func apply(to view: CodeEditorView, context: Context, forceSelection: Bool) {
        let font = editorFont(size: fontSize, monospace: monospace)
        let bold = editorFont(size: fontSize, monospace: monospace, weight: .semibold)
        view.backgroundColor = palette.background.uiColor
        view.gutter.backgroundColor = palette.gutter.uiColor
        view.gutter.numberColor = palette.secondary.uiColor
        view.gutter.font = editorFont(size: max(11, fontSize - 2), monospace: true)
        view.gutter.isHidden = !showLineNumbers
        view.showsLineNumbers = showLineNumbers

        let textView = view.textView
        textView.backgroundColor = palette.background.uiColor
        textView.font = font
        textView.textColor = palette.text.uiColor
        textView.tintColor = palette.text.uiColor
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text.uiColor,
        ]
        textView.autocorrectionType = monospace ? .no : .default
        textView.spellCheckingType = monospace ? .no : .default
        textView.smartQuotesType = monospace ? .no : .default
        textView.smartDashesType = monospace ? .no : .default
        textView.autocapitalizationType = monospace ? .none : .sentences
        applyWrap(softWrap, textView: textView)
        highlight(in: textView, font: font, bold: bold)
        view.invalidateLineNumbers()
        view.setNeedsLayout()

        guard forceSelection, let currentMatch, matches.indices.contains(currentMatch) else { return }
        let match = matches[currentMatch]
        let range = NSRange(location: match.utf16Location, length: match.utf16Length)
        guard NSMaxRange(range) <= textView.textStorage.length else { return }
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }

    private func highlight(in textView: UITextView, font: UIFont, bold: UIFont) {
        guard let layout = textView.layoutManager else { return }
        let length = textView.textStorage.length
        let full = NSRange(location: 0, length: length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        layout.removeTemporaryAttribute(.font, forCharacterRange: full)
        for token in tokens {
            let range = NSRange(location: token.utf16Offset, length: token.utf16Length)
            guard range.location >= 0, NSMaxRange(range) <= length else { continue }
            layout.addTemporaryAttribute(.foregroundColor, value: color(for: token.kind), forCharacterRange: range)
            if token.kind == .keyword, palette.keywordBold {
                layout.addTemporaryAttribute(.font, value: bold, forCharacterRange: range)
            }
        }
        for (index, match) in matches.enumerated() {
            let range = NSRange(location: match.utf16Location, length: match.utf16Length)
            guard range.location >= 0, NSMaxRange(range) <= length else { continue }
            let fill = index == currentMatch ? palette.currentMatch.uiColor : palette.match.uiColor
            layout.addTemporaryAttribute(.backgroundColor, value: fill, forCharacterRange: range)
        }
    }

    private func color(for kind: SyntaxKind) -> UIColor {
        switch kind {
        case .keyword:
            return palette.keyword.uiColor
        case .string:
            return palette.string.uiColor
        case .comment:
            return palette.comment.uiColor
        case .number:
            return palette.number.uiColor
        case .heading:
            return palette.heading.uiColor
        case .tag:
            return palette.keyword.uiColor
        }
    }

    private func applyWrap(_ wrap: Bool, textView: UITextView) {
        if wrap {
            textView.textContainer.widthTracksTextView = true
            textView.textContainer.lineBreakMode = .byWordWrapping
            textView.textContainer.size = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.lineBreakMode = .byClipping
            textView.textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private func editorFont(size: CGFloat, monospace: Bool, weight: UIFont.Weight = .regular) -> UIFont {
        if monospace {
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (String) -> Void
        var selectionNonce = -1
        weak var editor: CodeEditorView?

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func textViewDidChange(_ textView: UITextView) {
            editor?.invalidateLineNumbers()
            onChange(textView.text ?? "")
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            editor?.gutter.setNeedsDisplay()
        }
    }
}

final class CodeEditorView: UIView {
    let textView: UITextView
    let gutter = LineNumberGutter()
    var showsLineNumbers = true

    override init(frame: CGRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.widthTracksTextView = true
        textView = UITextView(frame: .zero, textContainer: container)
        super.init(frame: frame)
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 4, bottom: 48, right: 16)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.backgroundColor = .clear
        gutter.isUserInteractionEnabled = false
        gutter.isOpaque = true
        gutter.textView = textView
        addSubview(gutter)
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func invalidateLineNumbers() {
        gutter.lineStarts = nil
        gutter.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = showsLineNumbers ? gutter.requiredWidth : 0
        gutter.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        textView.frame = CGRect(x: width, y: 0, width: max(0, bounds.width - width), height: bounds.height)
        gutter.setNeedsDisplay()
    }
}

final class LineNumberGutter: UIView {
    weak var textView: UITextView?
    var font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    var numberColor = UIColor.secondaryLabel
    var lineStarts: [Int]?

    var requiredWidth: CGFloat {
        let count = max(lineStarts?.count ?? 1, 1)
        let digits = max(2, String(count).count)
        return CGFloat(digits) * font.pointSize * 0.68 + 18
    }

    override func draw(_ rect: CGRect) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let storage = textView.textStorage.string as NSString
        let starts = cachedStarts(in: storage)
        let visible = textView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textView.textContainer)
        guard glyphRange.location != NSNotFound else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: numberColor,
        ]
        for (line, start) in starts.enumerated() {
            var fragment = CGRect.zero
            if start < storage.length {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                guard glyph < layoutManager.numberOfGlyphs else { continue }
                fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else if layoutManager.numberOfGlyphs > 0 {
                let last = layoutManager.numberOfGlyphs - 1
                fragment = layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
                fragment.origin.y += fragment.height
            }
            let y = fragment.origin.y - textView.contentOffset.y + textView.textContainerInset.top
            let row = fragment.height > 0 ? fragment.height : font.lineHeight
            guard y + row >= 0, y <= bounds.height else { continue }
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: CGPoint(x: bounds.width - size.width - 8, y: y),
                withAttributes: attributes
            )
        }
    }

    private func cachedStarts(in text: NSString) -> [Int] {
        if let lineStarts { return lineStarts }
        var starts = [0]
        var index = 0
        while index < text.length {
            if text.character(at: index) == 10 {
                starts.append(index + 1)
            }
            index += 1
        }
        lineStarts = starts
        return starts
    }
}

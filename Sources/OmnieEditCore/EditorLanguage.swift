import Foundation

/// Languages supported by the v1 editor.
///
/// Keeping extension matching in the core makes the behavior easy to test and
/// keeps the UI independent from whichever editor engine renders the text.
public enum EditorLanguage: String, CaseIterable, Sendable {
    case plain
    case markdown
    case json
    case swift
    case python
    case javaScript
    case typeScript
    case html
    case css
    case shell
    case yaml
    case toml

    public init(fileURL: URL) {
        switch fileURL.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "json", "jsonc": self = .json
        case "swift": self = .swift
        case "py", "pyw": self = .python
        case "js", "jsx", "mjs", "cjs": self = .javaScript
        case "ts", "tsx", "mts", "cts": self = .typeScript
        case "html", "htm": self = .html
        case "css": self = .css
        case "sh", "bash", "zsh": self = .shell
        case "yaml", "yml": self = .yaml
        case "toml": self = .toml
        default: self = .plain
        }
    }
}

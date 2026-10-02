import SwiftUI

struct FindBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondary)
                .accessibilityHidden(true)
            TextField("Find", text: $editor.findQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.body.monospaced())
            Button {
                editor.caseInsensitive.toggle()
            } label: {
                Text("Aa")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 32, minHeight: 32)
            }
            .foregroundStyle(editor.caseInsensitive ? palette.secondary : palette.text)
            .accessibilityLabel(editor.caseInsensitive ? "Ignoring case" : "Matching case")
            Text(countLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.secondary)
                .frame(minWidth: 44, alignment: .trailing)
            Button {
                editor.stepMatch(-1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Previous match")
            Button {
                editor.stepMatch(1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Next match")
            Button {
                editor.isFinding = false
                editor.findQuery = ""
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Close find")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.gutter.color)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline.color).frame(height: 1)
        }
    }

    private var countLabel: String {
        guard !editor.findQuery.isEmpty else { return "" }
        guard !editor.matches.isEmpty else { return "0" }
        return "\(editor.matchIndex + 1)/\(editor.matches.count)"
    }
}

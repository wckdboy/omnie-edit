import SwiftUI
import OmnieEditCore

struct EditorView: View {
    let documentID: String
    @Bindable var appModel: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorModel?
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmingDelete = false
    @State private var shareURL: ShareItem?

    var body: some View {
        Group {
            if let editor {
                editing(editor)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .onAppear {
            if editor == nil {
                editor = appModel.makeEditor(id: documentID)
                if editor == nil {
                    dismiss()
                }
            }
            enforceLock()
        }
        .onChange(of: appModel.gate.unlockedDocumentIDs) { _, _ in
            enforceLock()
        }
        .onDisappear {
            editor?.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .omnieFlushSaves)) { _ in
            editor?.saveNow()
        }
    }

    @ViewBuilder
    private func editing(_ editor: EditorModel) -> some View {
        EditorTextView(
            text: editor.draft,
            tokens: SyntaxHighlighter.tokens(in: editor.draft, language: editor.language),
            matches: editor.matches,
            currentMatch: editor.matches.isEmpty ? nil : editor.matchIndex,
            selectionNonce: editor.selectionNonce,
            fontSize: appModel.settings.fontSize,
            monospace: appModel.settings.useMonospace,
            showLineNumbers: appModel.settings.showLineNumbers,
            softWrap: appModel.settings.softWrap,
            palette: palette,
            onChange: { editor.replaceDraft($0) }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editor.isFinding {
                FindBar(editor: editor)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(editor.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(editor.name)
                        .font(.headline)
                        .lineLimit(1)
                    if editor.isDirty {
                        Circle()
                            .fill(palette.text.color)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Unsaved changes")
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editor.isFinding.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Find")
                .keyboardShortcut("f", modifiers: .command)
                Button {
                    share(editor)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
                Menu {
                    Button("Save") { editor.saveNow() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!editor.isDirty)
                    Button("Rename") {
                        renameText = editor.name
                        renaming = true
                    }
                    lockButton(editor)
                    Button(appModel.settings.showLineNumbers ? "Hide line numbers" : "Show line numbers") {
                        appModel.settings.showLineNumbers.toggle()
                    }
                    Button(appModel.settings.softWrap ? "Disable soft wrap" : "Enable soft wrap") {
                        appModel.settings.softWrap.toggle()
                    }
                    Button(appModel.settings.useMonospace ? "Use proportional font" : "Use monospace") {
                        appModel.settings.useMonospace.toggle()
                    }
                    Button("Smaller text") {
                        appModel.settings.fontSize -= 1
                    }
                    Button("Larger text") {
                        appModel.settings.fontSize += 1
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("File name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { editor.rename(to: renameText) }
        }
        .confirmationDialog("Delete \(editor.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                appModel.delete(id: documentID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareURL) { item in
            ActivityView(items: [item.url])
        }
        .overlay(alignment: .bottomLeading) {
            if let saveError = editor.saveError, !editor.isFinding {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(palette.text.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.gutter.color)
            }
        }
    }

    @ViewBuilder
    private func lockButton(_ editor: EditorModel) -> some View {
        let locked = appModel.documents.first(where: { $0.id == documentID })?.isLocked ?? false
        if locked {
            Button("Unlock file") {
                Task {
                    if await appModel.unlockDocument(id: documentID) {
                        editor.saveNow()
                    }
                }
            }
        } else {
            Button("Lock file") {
                editor.saveNow()
                appModel.lockDocument(id: documentID)
                appModel.gate = appModel.gate.grantingDocumentUnlock(id: documentID)
            }
        }
    }

    private func share(_ editor: EditorModel) {
        editor.saveNow()
        do {
            shareURL = ShareItem(url: try appModel.store.exportURL(id: documentID))
        } catch {
            editor.report(error.localizedDescription)
        }
    }

    private func enforceLock() {
        guard let document = appModel.documents.first(where: { $0.id == documentID }) else { return }
        if appModel.gate.needsDocumentUnlock(id: document.id, isLocked: document.isLocked) {
            dismiss()
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

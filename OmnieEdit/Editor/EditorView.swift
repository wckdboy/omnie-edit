import OmnieEditCore
import SwiftUI

struct EditorView: View {
    let tabID: UUID
    @Bindable var appModel: AppModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let tab = appModel.selectedTab {
                EditorContent(tab: tab, appModel: appModel)
            } else {
                ContentUnavailableView(
                    "No Open File",
                    systemImage: "doc",
                    description: Text("Open a file to start editing.")
                )
            }
        }
        .onAppear {
            appModel.selectTab(id: tabID)
        }
        .onChange(of: appModel.tabs.isEmpty) { _, isEmpty in
            if isEmpty {
                dismiss()
            }
        }
    }
}

private struct EditorContent: View {
    @Bindable var tab: EditorTab
    @Bindable var appModel: AppModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var command: CodeEditorCommand?
    @State private var showingGoToLine = false
    @State private var lineNumber = ""
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingMarkdownPreview = false
    @State private var shareItem: ShareItem?

    private var palette: Palette {
        Palette.resolve(appModel.settings.theme, colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            if showingMarkdownPreview, tab.language == .markdown {
                MarkdownPreview(text: tab.text, palette: palette)
            } else {
                RunestoneCodeEditor(
                    text: textBinding,
                    language: tab.language,
                    showLineNumbers: appModel.settings.showLineNumbers,
                    softWrap: appModel.settings.softWrap,
                    fontSize: appModel.settings.fontSize,
                    colorTheme: palette.editorColorTheme,
                    command: command
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .navigationTitle(tab.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                editorToolbar
            }
        }
        .alert("Go to Line", isPresented: $showingGoToLine) {
            TextField("Line number", text: $lineNumber)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Go") {
                guard let line = Int(lineNumber), line > 0 else { return }
                command = .goToLine(line, UUID())
            }
        } message: {
            Text("Enter a line number in the current file.")
        }
        .alert("Rename File", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                appModel.renameOpenFile(tab, to: renameText)
            }
        } message: {
            Text("Include the extension to change the file's type, e.g. notes.md")
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .overlay(alignment: .bottom) {
            if let saveError = tab.saveError {
                saveErrorToast(saveError)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func saveErrorToast(_ message: String) -> some View {
        let label = Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular.tint(.red), in: Capsule())
        } else {
            label.background(.red, in: Capsule())
        }
    }

    @ViewBuilder
    private var tabStrip: some View {
        if #available(iOS 26.0, *) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(appModel.tabs) { openTab in
                            if openTab.id == tab.id {
                                tabChip(for: openTab)
                                    .foregroundStyle(.white)
                                    .gradientGlassBackground(in: Capsule())
                            } else {
                                tabChip(for: openTab)
                                    .glassEffect(.regular.interactive(), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel("Open files")
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(appModel.tabs) { openTab in
                        tabChip(for: openTab)
                            .background(
                                openTab.id == tab.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09),
                                in: Capsule()
                            )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .scrollIndicators(.hidden)
            .background(.bar)
            .accessibilityLabel("Open files")
        }
    }

    private func tabChip(for openTab: EditorTab) -> some View {
        HStack(spacing: 5) {
            Button {
                appModel.selectTab(id: openTab.id)
            } label: {
                HStack(spacing: 5) {
                    Text(openTab.name)
                        .lineLimit(1)
                    if openTab.isDirty {
                        Circle()
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.plain)

            Button("Close \(openTab.name)", systemImage: "xmark") {
                Task {
                    await appModel.saveAndCloseTab(id: openTab.id)
                }
            }
            .labelStyle(.iconOnly)
            .font(.caption2)
        }
        .font(.caption)
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var editorToolbar: some View {
        if appModel.settings.preferredHand == .right {
            Spacer()
            findButton
            undoButton
            saveButton
            moreMenu
        } else {
            moreMenu
            saveButton
            undoButton
            findButton
            Spacer()
        }
    }

    private var saveButton: some View {
        Button(
            tab.isDirty ? "Save" : "Saved",
            systemImage: tab.isDirty ? "square.and.arrow.down" : "checkmark.circle"
        ) {
            Task {
                await appModel.saveSelectedTab()
            }
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!tab.isDirty)
        .accessibilityHint(
            tab.isDirty
                ? "Saves changes to the original file"
                : "All changes are saved"
        )
    }

    private var findButton: some View {
        Button("Find", systemImage: "magnifyingglass") {
            command = .find(UUID())
        }
        .keyboardShortcut("f", modifiers: .command)
    }

    private var undoButton: some View {
        Menu("Edit History", systemImage: "arrow.uturn.backward") {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                command = .undo(UUID())
            }
            Button("Redo", systemImage: "arrow.uturn.forward") {
                command = .redo(UUID())
            }
        }
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Rename", systemImage: "pencil") {
                renameText = tab.name
                showingRename = true
            }

            Button("Go to Line", systemImage: "number") {
                lineNumber = ""
                showingGoToLine = true
            }

            if tab.language == .markdown {
                Button(
                    showingMarkdownPreview ? "Show Editor" : "Preview Markdown",
                    systemImage: showingMarkdownPreview ? "pencil" : "eye"
                ) {
                    showingMarkdownPreview.toggle()
                }
            }

            Button(
                appModel.settings.showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers",
                systemImage: "list.number"
            ) {
                appModel.settings.showLineNumbers.toggle()
            }

            Button(
                appModel.settings.softWrap ? "Disable Soft Wrap" : "Enable Soft Wrap",
                systemImage: "text.word.spacing"
            ) {
                appModel.settings.softWrap.toggle()
            }

            Divider()

            Button("Share File", systemImage: "square.and.arrow.up") {
                Task {
                    await appModel.saveSelectedTab()
                    guard tab.saveError == nil else { return }
                    shareItem = ShareItem(url: tab.url)
                }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { tab.text },
            set: { newText in
                guard tab.text != newText else { return }
                tab.text = newText
                appModel.textDidChange(in: tab)
            }
        )
    }
}

private struct MarkdownPreview: View {
    let text: String
    let palette: Palette

    private var renderedText: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var body: some View {
        ScrollView {
            Text(renderedText)
                .foregroundStyle(palette.text.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(20)
        }
        .background(palette.background.color)
        .accessibilityLabel("Markdown preview")
    }
}

private struct ShareItem: Identifiable {
    let url: URL

    var id: String { url.path }
}

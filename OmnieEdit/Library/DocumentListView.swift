import OmnieEditCore
import SwiftUI
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var path: [LibraryRoute] = []
    @State private var query = ""
    @State private var creating = false
    @State private var importing = false
    @State private var renameTarget: LibraryDocument?
    @State private var renameText = ""
    @State private var deleteTarget: LibraryDocument?

    private var filtered: [LibraryDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.documents }
        return model.documents.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.documents.isEmpty {
                    empty
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    list
                }
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Omnie-edit")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case let .editor(id):
                    EditorView(documentID: id, appModel: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
            .searchable(text: $query, prompt: "Find a file")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import")
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New file")
                    Button {
                        path.append(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $creating) {
                NewDocumentSheet(model: model) { document in
                    path.append(.editor(document.id))
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: importTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case let .success(urls):
                    for url in urls {
                        model.importFile(at: url)
                    }
                case let .failure(error):
                    model.lastError = error.localizedDescription
                }
            }
            .alert("Rename", isPresented: renamePresented) {
                TextField("File name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Rename") {
                    if let renameTarget {
                        model.rename(id: renameTarget.id, to: renameText)
                    }
                    renameTarget = nil
                }
            }
            .confirmationDialog(
                "Delete \(deleteTarget?.name ?? "this file")?",
                isPresented: deletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deleteTarget {
                        model.delete(id: deleteTarget.id)
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK") { model.lastError = nil }
            } message: {
                Text(model.lastError ?? "")
            }
            .onChange(of: model.gate.needsAppUnlock) { _, needs in
                if needs {
                    path.removeAll()
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { document in
                Button {
                    open(document)
                } label: {
                    row(document)
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.background.color)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        deleteTarget = document
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(document.isLocked ? "Unlock" : "Lock") {
                        toggleLock(document)
                    }
                    .tint(palette.secondary.color)
                }
                .contextMenu {
                    Button("Rename") {
                        renameText = document.name
                        renameTarget = document
                    }
                    Button(document.isLocked ? "Unlock" : "Lock") {
                        toggleLock(document)
                    }
                    Button("Delete", role: .destructive) {
                        deleteTarget = document
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { model.reload() }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("No files yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.text.color)
            Text("Text and source you edit here stay on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(palette.secondary.color)
                .multilineTextAlignment(.center)
            Button("New file") { creating = true }
                .buttonStyle(.borderedProminent)
                .tint(palette.text.color)
                .foregroundStyle(palette.background.color)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ document: LibraryDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if document.isLocked {
                    Image(systemName: "lock")
                        .font(.caption)
                        .foregroundStyle(palette.secondary.color)
                        .accessibilityLabel("Locked")
                }
                Text(document.name)
                    .font(.body.monospaced())
                    .foregroundStyle(palette.text.color)
                    .lineLimit(1)
            }
            Text(meta(document))
                .font(.caption)
                .foregroundStyle(palette.secondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func meta(_ document: LibraryDocument) -> String {
        let date = document.modifiedAt.formatted(.relative(presentation: .named))
        return "\(date) · \(ByteCount.string(document.byteCount))"
    }

    private func open(_ document: LibraryDocument) {
        Task {
            if await model.authorizeOpen(of: document) {
                path.append(.editor(document.id))
            }
        }
    }

    private func toggleLock(_ document: LibraryDocument) {
        if document.isLocked {
            Task { _ = await model.unlockDocument(id: document.id) }
        } else {
            model.lockDocument(id: document.id)
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText, .text, .sourceCode, .json, .html, .xml, .shellScript]
        let extras = ["css", "md", "swift", "py", "ts", "go", "rs", "yaml", "yml", "sql", "toml", "sh"]
        for ext in extras {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}

enum LibraryRoute: Hashable {
    case editor(String)
    case settings
}

enum ByteCount {
    static func string(_ count: Int64) -> String {
        switch count {
        case ..<1024:
            return "\(count) B"
        case ..<1024 * 1024:
            return String(format: "%.0f KB", Double(count) / 1024)
        default:
            let megabytes = Double(count) / 1024 / 1024
            return String(format: "%.1f MB", megabytes)
        }
    }
}

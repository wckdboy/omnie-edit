import OmnieEditCore
import SwiftUI
import UniformTypeIdentifiers

/// Keeps the given item out of the shared Liquid Glass background other
/// bottom-bar items merge into, so it reads as its own standalone control.
@ToolbarContentBuilder
private func standaloneToolbarItem<Content: View>(_ content: Content) -> some ToolbarContent {
    if #available(iOS 26.0, *) {
        ToolbarItem(placement: .bottomBar) { content }
            .sharedBackgroundVisibility(.hidden)
    } else {
        ToolbarItem(placement: .bottomBar) { content }
    }
}

enum WorkspaceRoute: Hashable {
    case project
    case editor(UUID)
    case git
    case settings
}

struct DocumentListView: View {
    @Bindable var model: AppModel

    @State private var path: [WorkspaceRoute] = []
    @State private var importingFiles = false
    @State private var importingProject = false
    @State private var exportingNewFile = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.recents.isEmpty {
                    emptyState
                } else {
                    recentList
                }
            }
            .navigationTitle("Omnie Edit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkspaceRoute.self) { route in
                switch route {
                case .project:
                    ProjectBrowserView(model: model, path: $path)
                case let .editor(tabID):
                    EditorView(tabID: tabID, appModel: model)
                case .git:
                    GitView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("OmnieLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .accessibilityLabel("Omnie Edit")
                }
                bottomToolbarContent
            }
            .fileImporter(
                isPresented: $importingFiles,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onCompletion: importFiles
            )
            .fileImporter(
                isPresented: $importingProject,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: importProject
            )
            .fileExporter(
                isPresented: $exportingNewFile,
                document: EmptyTextDocument(),
                contentType: .plainText,
                defaultFilename: "Untitled.txt",
                onCompletion: finishNewFile
            )
            .alert("Couldn’t complete that action", isPresented: errorIsPresented) {
                Button("OK") {
                    model.lastError = nil
                }
            } message: {
                Text(model.lastError ?? "")
            }
        }
    }

    private var recentList: some View {
        List {
            let projects = model.recents.filter { $0.kind == .project }
            let files = model.recents.filter { $0.kind == .file }

            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { item in
                        recentRow(item)
                    }
                }
            }

            if !files.isEmpty {
                Section("Files") {
                    ForEach(files) { item in
                        recentRow(item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Open a file or project", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Omnie Edit works directly with documents in Files. Your work stays where you put it.")
        } actions: {
            Button("Open File") {
                importingFiles = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .foregroundStyle(Color(uiColor: .systemBackground))

            Button("Open Project Folder") {
                importingProject = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func recentRow(_ item: RecentWorkspace) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.kind == .project ? "folder.fill" : "doc.text")
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(item.kind == .project ? .yellow : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(item.lastOpenedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Remove", systemImage: "xmark", role: .destructive) {
                model.removeRecent(id: item.id)
            }
        }
        .contextMenu {
            Button("Remove from Recents", systemImage: "xmark") {
                model.removeRecent(id: item.id)
            }
        }
        .accessibilityHint("Opens this \(item.kind == .project ? "project" : "file")")
    }

    @ToolbarContentBuilder
    private var bottomToolbarContent: some ToolbarContent {
        if model.settings.preferredHand == .right {
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) { settingsButton }
            ToolbarItem(placement: .bottomBar) { openMenu }
            standaloneToolbarItem(newFileButton)
        } else {
            standaloneToolbarItem(newFileButton)
            ToolbarItem(placement: .bottomBar) { openMenu }
            ToolbarItem(placement: .bottomBar) { settingsButton }
            ToolbarItem(placement: .bottomBar) { Spacer() }
        }
    }

    private var settingsButton: some View {
        Button {
            path.append(.settings)
        } label: {
            Image(systemName: "gearshape")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
        .accessibilityShowsLargeContentViewer {
            Label("Settings", systemImage: "gearshape")
        }
    }

    private var openMenu: some View {
        Menu {
            Button("Open File", systemImage: "doc") {
                importingFiles = true
            }
            Button("Open Project Folder", systemImage: "folder") {
                importingProject = true
            }
        } label: {
            Image(systemName: "folder")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Open")
        .accessibilityShowsLargeContentViewer {
            Label("Open", systemImage: "folder")
        }
    }

    private var newFileButton: some View {
        Button {
            exportingNewFile = true
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .primaryGlassIcon()
        }
        .accessibilityLabel("New File")
        .accessibilityHint("Creates a new text file in Files")
        .accessibilityShowsLargeContentViewer {
            Label("New File", systemImage: "plus")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }

    private func open(_ item: RecentWorkspace) {
        switch model.openRecent(item) {
        case let .file(tabID):
            path.append(.editor(tabID))
        case .project:
            path.append(.project)
        case nil:
            break
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            var lastOpenedTabID: UUID?
            for url in try result.get() {
                if let tabID = model.openPickedFile(url) {
                    lastOpenedTabID = tabID
                }
            }
            if let lastOpenedTabID {
                path.append(.editor(lastOpenedTabID))
            }
        } catch {
            model.report(error)
        }
    }

    private func importProject(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            if model.openPickedProject(url) {
                path.append(.project)
            }
        } catch {
            model.report(error)
        }
    }

    private func finishNewFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            if let tabID = model.openPickedFile(url) {
                path.append(.editor(tabID))
            }
        } catch {
            model.report(error)
        }
    }
}

private struct EmptyTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}

private struct ProjectBrowserView: View {
    @Bindable var model: AppModel
    @Binding var path: [WorkspaceRoute]

    @State private var query = ""
    @State private var searchResults: [ProjectEntry] = []
    @State private var isSearching = false
    @State private var newItemKind: NewProjectItemKind?
    @State private var newItemName = ""
    @State private var renameTarget: ProjectEntry?
    @State private var renameName = ""
    @State private var deleteTarget: ProjectEntry?
    @State private var moveTarget: ProjectEntry?
    @State private var moveDestinations: [ProjectFolderDestination] = []
    @State private var isLoadingMoveDestinations = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleEntries: [ProjectEntry] {
        guard !trimmedQuery.isEmpty else { return model.projectEntries }
        return searchResults
    }

    var body: some View {
        Group {
            if isSearching && visibleEntries.isEmpty {
                ProgressView("Searching Project")
            } else if visibleEntries.isEmpty, trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "Empty Folder",
                    systemImage: "folder",
                    description: Text("Create a file or folder to get started.")
                )
            } else if visibleEntries.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(visibleEntries) { entry in
                    entryRow(entry)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(model.currentFolderTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find in project")
        .task(id: query) {
            guard !trimmedQuery.isEmpty else {
                searchResults = []
                isSearching = false
                return
            }
            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                searchResults = await model.searchProject(for: trimmedQuery)
            } catch {
                return
            }
            isSearching = false
        }
        .toolbar {
            projectToolbarContent
        }
        .alert(newItemKind?.title ?? "New Item", isPresented: creatingItem) {
            TextField(newItemKind?.prompt ?? "Name", text: $newItemName)
            Button("Cancel", role: .cancel) {
                resetNewItem()
            }
            Button("Create") {
                createItem()
            }
        }
        .alert("Rename Item", isPresented: renamingItem) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Rename") {
                if let renameTarget {
                    model.renameProjectItem(renameTarget, to: renameName)
                }
                renameTarget = nil
            }
        }
        .alert(deleteTitle, isPresented: deletingItem) {
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    model.deleteProjectItem(deleteTarget)
                }
                deleteTarget = nil
            }
        } message: {
            Text(deleteMessage)
        }
        .sheet(item: $moveTarget) { entry in
            NavigationStack {
                Group {
                    if isLoadingMoveDestinations {
                        ProgressView("Finding folders…")
                    } else if moveDestinations.isEmpty {
                        ContentUnavailableView(
                            "No Destination Folders",
                            systemImage: "folder",
                            description: Text("Create another folder before moving this item.")
                        )
                    } else {
                        List(moveDestinations) { destination in
                            Button {
                                model.moveProjectItem(entry, to: destination.url)
                                moveTarget = nil
                            } label: {
                                Label(destination.title, systemImage: "folder")
                            }
                        }
                    }
                }
                .navigationTitle("Move “\(entry.name)”")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            moveTarget = nil
                        }
                    }
                }
            }
            .task(id: entry.id) {
                isLoadingMoveDestinations = true
                moveDestinations = await model.moveDestinations(for: entry)
                isLoadingMoveDestinations = false
            }
        }
    }

    private func entryRow(_ entry: ProjectEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                open(entry)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                        .foregroundStyle(entry.isDirectory ? .yellow : .secondary)
                        .frame(width: 24)
                    Text(entry.name)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                    if entry.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                projectItemActions(entry)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(entry.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = entry
            }
            Button("Rename", systemImage: "pencil") {
                beginRename(entry)
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Move", systemImage: "folder") {
                beginMove(entry)
            }
            .tint(.indigo)
        }
        .contextMenu {
            projectItemActions(entry)
        }
    }

    @ViewBuilder
    private func projectItemActions(_ entry: ProjectEntry) -> some View {
        Button("Rename", systemImage: "pencil") {
            beginRename(entry)
        }
        Button("Move to Folder", systemImage: "folder") {
            beginMove(entry)
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            model.duplicateProjectItem(entry)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            deleteTarget = entry
        }
    }

    @ToolbarContentBuilder
    private var projectToolbarContent: some ToolbarContent {
        if model.settings.preferredHand == .right {
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) { parentButton }
            ToolbarItem(placement: .bottomBar) { gitButton }
            ToolbarItem(placement: .bottomBar) { editorButton }
            standaloneToolbarItem(createMenu)
        } else {
            standaloneToolbarItem(createMenu)
            ToolbarItem(placement: .bottomBar) { editorButton }
            ToolbarItem(placement: .bottomBar) { gitButton }
            ToolbarItem(placement: .bottomBar) { parentButton }
            ToolbarItem(placement: .bottomBar) { Spacer() }
        }
    }

    private var parentButton: some View {
        Button("Parent Folder", systemImage: "chevron.left") {
            query = ""
            model.leaveFolder()
        }
        .disabled(model.isAtProjectRoot)
    }

    private var createMenu: some View {
        Menu {
            Button("New File", systemImage: "doc.badge.plus") {
                beginCreate(.file)
            }
            Button("New Folder", systemImage: "folder.badge.plus") {
                beginCreate(.folder)
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .primaryGlassIcon()
        }
        .accessibilityLabel("Create")
        .accessibilityHint("Creates a new file or folder")
        .accessibilityShowsLargeContentViewer {
            Label("Create", systemImage: "plus")
        }
    }

    private var editorButton: some View {
        Button("Open Editor", systemImage: "rectangle.stack") {
            if let selectedTabID = model.selectedTabID {
                path.append(.editor(selectedTabID))
            }
        }
        .disabled(model.selectedTabID == nil)
    }

    private var gitButton: some View {
        Button("Git", systemImage: model.projectUsesGit ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted") {
            path.append(.git)
        }
    }

    private var creatingItem: Binding<Bool> {
        Binding(
            get: { newItemKind != nil },
            set: { if !$0 { resetNewItem() } }
        )
    }

    private var renamingItem: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletingItem: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var deleteTitle: String {
        guard let deleteTarget else { return "Delete Item?" }
        return "Delete “\(deleteTarget.name)”?"
    }

    private var deleteMessage: String {
        guard let deleteTarget else { return "" }
        if deleteTarget.isDirectory {
            return "This permanently deletes the folder and everything inside it. This action cannot be undone."
        }
        return "This permanently deletes the file. This action cannot be undone."
    }

    private func open(_ entry: ProjectEntry) {
        if entry.isDirectory {
            query = ""
            model.enterFolder(entry.url)
        } else if let tabID = model.openProjectFile(entry.url) {
            path.append(.editor(tabID))
        }
    }

    private func beginMove(_ entry: ProjectEntry) {
        moveDestinations = []
        isLoadingMoveDestinations = true
        moveTarget = entry
    }

    private func beginCreate(_ kind: NewProjectItemKind) {
        newItemKind = kind
        newItemName = kind == .file ? "Untitled.txt" : "New Folder"
    }

    private func resetNewItem() {
        newItemKind = nil
        newItemName = ""
    }

    private func createItem() {
        switch newItemKind {
        case .file:
            model.createProjectFile(named: newItemName)
            if let selectedTabID = model.selectedTabID {
                path.append(.editor(selectedTabID))
            }
        case .folder:
            model.createProjectFolder(named: newItemName)
        case nil:
            break
        }
        resetNewItem()
    }

    private func beginRename(_ entry: ProjectEntry) {
        renameTarget = entry
        renameName = entry.name
    }
}

private enum NewProjectItemKind {
    case file
    case folder

    var title: String {
        switch self {
        case .file: "New File"
        case .folder: "New Folder"
        }
    }

    var prompt: String {
        switch self {
        case .file: "File name"
        case .folder: "Folder name"
        }
    }
}

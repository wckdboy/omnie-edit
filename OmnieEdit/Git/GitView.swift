import OmnieEditCore
import SwiftUI

struct GitView: View {
    @Bindable var model: AppModel

    @State private var commitMessage = ""
    @State private var selectedDiff: GitFileDiff?
    @State private var discardTarget: GitStatusItem?
    @State private var isWorking = false

    var body: some View {
        Group {
            if !model.projectUsesGit {
                disabledState
            } else if model.gitStatus.isEmpty {
                cleanState
            } else {
                statusList
            }
        }
        .navigationTitle("Git")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refreshGitStatus()
        }
        .refreshable {
            await model.refreshGitStatus()
        }
        .sheet(item: diffBinding) { diff in
            GitDiffView(diff: diff)
        }
        .alert("Discard changes to \(discardTarget?.path ?? "this file")?", isPresented: discarding) {
            Button("Cancel", role: .cancel) {
                discardTarget = nil
            }
            Button("Discard", role: .destructive) {
                guard let target = discardTarget else { return }
                discardTarget = nil
                Task {
                    isWorking = true
                    await model.discardGitChanges(path: target.path)
                    isWorking = false
                }
            }
        } message: {
            Text("This replaces the working copy with Git’s version. An untracked file will be permanently deleted.")
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var disabledState: some View {
        ContentUnavailableView {
            Label("Git is Off", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("This project is not a repository. You can initialize Git locally without adding a remote.")
        } actions: {
            Button("Enable Git") {
                Task {
                    isWorking = true
                    await model.enableGit()
                    isWorking = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var cleanState: some View {
        ContentUnavailableView {
            Label("Working Tree Clean", systemImage: "checkmark.circle")
        } description: {
            Text("There are no changes to commit.")
        }
    }

    private var statusList: some View {
        List {
            Section("Changes") {
                ForEach(model.gitStatus) { item in
                    statusRow(item)
                }
            }

            Section {
                TextField("Commit message", text: $commitMessage, axis: .vertical)
                    .lineLimit(2...5)

                Button("Commit Staged Changes", systemImage: "checkmark.circle") {
                    Task {
                        isWorking = true
                        if await model.commitGitChanges(message: commitMessage) {
                            commitMessage = ""
                        }
                        isWorking = false
                    }
                }
                .disabled(
                    commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !model.gitStatus.contains(where: \.isStaged)
                )
            } header: {
                Text("Commit")
            } footer: {
                if model.gitIdentity == nil {
                    Text("Add your Git name and email in Settings before committing.")
                } else {
                    Text("Commits are local. No remote repository is required.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statusRow(_ item: GitStatusItem) -> some View {
        Button {
            Task {
                selectedDiff = await model.gitDiff(path: item.path)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isStaged ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isStaged ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.path)
                        .foregroundStyle(.primary)
                    Text(item.states.map(\.label).joined(separator: ", "))
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Discard", systemImage: "arrow.uturn.backward", role: .destructive) {
                discardTarget = item
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Stage", systemImage: "plus") {
                Task {
                    isWorking = true
                    await model.stageGitFile(path: item.path)
                    isWorking = false
                }
            }
            .tint(.green)
        }
        .contextMenu {
            Button("View Diff", systemImage: "doc.text.magnifyingglass") {
                Task {
                    selectedDiff = await model.gitDiff(path: item.path)
                }
            }
            Button("Stage File", systemImage: "plus") {
                Task {
                    isWorking = true
                    await model.stageGitFile(path: item.path)
                    isWorking = false
                }
            }
            Button("Discard Changes", systemImage: "arrow.uturn.backward", role: .destructive) {
                discardTarget = item
            }
        }
    }

    private var diffBinding: Binding<GitFileDiff?> {
        Binding(
            get: { selectedDiff },
            set: { selectedDiff = $0 }
        )
    }

    private var discarding: Binding<Bool> {
        Binding(
            get: { discardTarget != nil },
            set: { if !$0 { discardTarget = nil } }
        )
    }
}

private struct GitDiffView: View {
    let diff: GitFileDiff

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.kind.foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(line.kind.background)
                    }
                }
                .textSelection(.enabled)
            }
            .navigationTitle(diff.path)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension GitFileState {
    var label: String {
        switch self {
        case .added: "Added"
        case .changed: "Changed"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .untracked: "Untracked"
        case .conflicted: "Conflicted"
        }
    }
}

private extension GitPatchLine.Kind {
    var foreground: Color {
        switch self {
        case .addition: .green
        case .deletion: .red
        case .header: .secondary
        case .context: .primary
        }
    }

    var background: Color {
        switch self {
        case .addition: Color.green.opacity(0.10)
        case .deletion: Color.red.opacity(0.10)
        case .header: Color.secondary.opacity(0.08)
        case .context: .clear
        }
    }
}

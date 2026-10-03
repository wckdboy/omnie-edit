# Omnie Edit

Omnie Edit is a focused, real-file code and text editor for iPhone. It opens files and project folders from the system document picker, edits them in place, and keeps recent locations as security-scoped bookmarks. There is no required account and no private document database.

The project is being rebuilt from `BUILD_PLAN.md`. The current vertical slice includes:

- Real UTF-8 file access through `NSFileCoordinator`.
- Recent files and project folders without copying user content.
- One-level project navigation with `.gitignore` support and a hidden `.git` directory.
- Create, rename, duplicate, and confirmed recursive delete operations.
- Runestone editing with Tree-sitter highlighting for the v1 language set.
- Up to eight tabs, debounced autosave, native find, go-to-line, undo/redo, and Markdown preview.
- Right-handed controls by default, with a mirrored left-handed mode.
- Local Git repository detection and creation, status, whole-file staging, diff, commit, and confirmed discard.

Remote Git authentication, clone, pull, and push are planned for the build plan’s v1.1 milestone.

## Requirements

- Xcode 27 or later
- iOS 18 or later

## Local development

1. Open `OmnieEdit.xcodeproj` in Xcode.
2. Select the `OmnieEdit` scheme and an iPhone simulator or device.
3. Build and run.

No remote repository or hosted CI service is required. Product > Test runs the unit suite locally.

## Architecture

- `OmnieEdit/` contains the SwiftUI application and its observable app model.
- `Sources/OmnieEditCore/Workspace.swift` owns bookmark, coordinated-I/O, recents, and project-file behavior.
- `Sources/OmnieEditCore/RunestoneCodeEditor.swift` is the single Runestone integration boundary.
- `Tests/OmnieEditCoreTests/` contains deterministic file-system and editing tests.

The app stores bookmark metadata and preferences in `UserDefaults`. File contents remain at the URLs selected by the user. File access must flow through `WorkspaceBookmark`, `CoordinatedTextFile`, or `ProjectFileSystem`; UI code should not add ad-hoc reads and writes.

## Dependencies

- [Runestone](https://github.com/simonbs/Runestone) — editor engine, MIT licensed.
- [TreeSitterLanguages](https://github.com/simonbs/TreeSitterLanguages) — Runestone language adapters, MIT licensed.
- [SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX) — Swift Git API, MIT licensed.
- [libgit2](https://libgit2.org/) — Git implementation, GPL-2.0-only with a linking exception.

Dependency notices are recorded in `THIRD_PARTY_NOTICES.md`. Dependencies are declared in `Package.swift` and resolved by Xcode/Swift Package Manager.

## Contributing

See `CONTRIBUTING.md`. New behavior should have focused tests, descriptive names, and comments only where the reason is not obvious from the code.

## Privacy

See `PRIVACY.md`. Omnie Edit does not require an account and does not include analytics or advertising SDKs.

## License

Omnie Edit is available under the MIT License. See `LICENSE`.

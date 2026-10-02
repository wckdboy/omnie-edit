# Omnie-edit

Omnie-edit is a minimal text and source editor for iPhone. It is a quiet place to open a file, change it, and leave. It is not a notes suite, and it does not sync.

Unlocked files live in a shared app-group folder so another Omnie app on the same iPhone, including **omnie-ios**, can list them and read their contents. Nothing in this app opens a network connection. There is no analytics SDK.

## Requirements

- Xcode 16 or later
- iOS 17 or later
- An Apple Developer team on the same account as omnie-ios, if you want the shared folder and the Files app provider

The editor still runs if the app group is not entitled yet. In that case files stay in the app’s private Application Support folder, and Settings says so.

## Run

1. Open `OmnieEdit.xcodeproj`.
2. Select the **OmnieEdit** scheme and an iPhone simulator or a device.
3. On the OmnieEdit and OmnieFileProvider targets, set your team under Signing & Capabilities.
4. Confirm both targets use the App Group `group.app.omnie.edit` (the entitlements files already request it). Create that group on the developer account if Xcode asks.
5. Run.

Debug builds of the file provider include `com.apple.developer.fileprovider.testing-mode` so the domain can load before the account has the production File Provider capability. `OmnieFileProvider/Release.entitlements` does not include that key. Use the Release entitlements for an App Store archive.

Hardware keyboard shortcuts in the editor: Command-F finds, Command-S saves.

## Tests

From the repository root, with Swift 5.9 or later:

```sh
swift test
```

That runs the logic tests: file names, the catalog contract, the document store, lock and session policy, settings, search, and syntax highlighting. In Xcode, Product > Test runs the same files on the iOS simulator.

## What the editor does

- Create, import, rename, and delete UTF-8 text and source files.
- Edit with a monospace font (proportional is available), optional line numbers, soft wrap, and find-in-file.
- Highlight Swift, Python, JavaScript, TypeScript, JSON, HTML, CSS, shell, Go, Rust, C, C++, Ruby, YAML, SQL, TOML, and Markdown. The highlighter is in the app. There is no third-party parsing library.
- Autosave shortly after you stop typing, and save explicitly from the menu. A dot beside the file name means the buffer is unsaved. Leaving the editor or switching away flushes the buffer.
- Share a copy, or import from Files. “Open in Omnie-edit” copies the file in. v1 does not edit documents in place outside its own folder.
- Theme: system, light, dark, or monochrome. Font size, default extension, line numbers, wrap, and monospace are in Settings.
- Optional Face ID or device passcode to open the app. Optional per-file lock.

## Privacy and security

Omnie-edit does not ship a network client, an analytics SDK, or an account system. It does not use the Keychain in v1.

**Data Protection.** Every save asks for `NSFileProtectionComplete` (`Data.WritingOptions.completeFileProtection`, and the same class on the file). The file is encrypted by iOS and cannot be read while the device is locked. That applies to Omnie-edit, to omnie-ios, and to the File Provider. If a save fails because the device locked mid-edit, the buffer stays dirty.

**App lock.** Opt in under Settings. After the app goes to the background, the next open requires Face ID, Touch ID, or the device passcode (`LAPolicy.deviceOwnerAuthentication`). While the system is capturing an app-switcher snapshot, the editor is covered. The lock is a gate on this app’s interface. It does not hide the shared folder from a peer that is entitled to the app group.

**Per-file lock.** Locking a file moves it out of the shared folder into the app-private container and drops it from `catalog.json`. omnie-ios cannot list or read it. Unlocking requires Face ID or the passcode, then moves the same document id back into the shared folder. This is not a second encryption password. The cryptographic boundary is Data Protection plus who is allowed into the app group. Prefer not to add unrelated apps to `group.app.omnie.edit`.

**Backup.** Files are excluded from device backup by default, including iCloud Backup. Turn on “Include in device backup” if you want the system backup to keep them. Omnie-edit still does not upload anything itself.

**Privacy manifest.** `PrivacyInfo.xcprivacy` declares no tracking and no collected data. The only required-reason APIs are UserDefaults (settings) and file timestamps (the modified date shown in the list).

## Local API for omnie-ios

This is the v1 contract. Omnie-edit is the only writer. Peers read.

### Entitlement

Both apps, same team:

```xml
<key>com.apple.security.application-groups</key>
<array>
  <string>group.app.omnie.edit</string>
</array>
```

### On disk

Paths are relative to the app group container:

```text
OmnieEdit/catalog.json
OmnieEdit/Documents/<file name>
```

`catalog.json` is replaced atomically. v1 is a flat directory: `relativePath` is a single path component. Reject `.`, `..`, separators, leading dots, and control characters.

Dates are ISO-8601 in UTC (`2026-10-02T18:00:00Z`). Text is UTF-8. A leading UTF-8 BOM is stripped on read. Unknown JSON keys may be added without a version bump; decoders ignore them. A different `contractVersion` is a breaking change and must be rejected.

Sort, if you do not use the helper: `modifiedAt` descending, then `name` case-insensitive, then `id`.

An example document is in `Contract/catalog.example.json`.

```json
{
  "contractVersion": 1,
  "generatedAt": "2026-10-02T18:00:01Z",
  "documents": [
    {
      "id": "7f2c9c2e-1b4a-4e0a-9c11-6a1d0e5b9a10",
      "name": "ContentView.swift",
      "extension": "swift",
      "relativePath": "ContentView.swift",
      "byteCount": 42,
      "modifiedAt": "2026-10-02T18:00:00Z"
    }
  ]
}
```

Entries whose path is unsafe, or whose file is missing, are skipped. Do not follow a tampered `relativePath` outside `Documents`.

### Swift package

Link the **OmnieDocumentKit** product from this package. Do not link **OmnieEditCore** from omnie-ios. That module creates, renames, locks, and writes, and those mutations are not part of the peer contract.

```swift
import OmnieDocumentKit

let root = try OmnieContract.requireSharedRoot()
let catalog = OmnieDocumentCatalog(rootURL: root)
let documents = try catalog.list()
let source = try catalog.read(id: documents[0].id)
let fileURL = try catalog.fileURL(id: documents[0].id)
```

`requireSharedRoot()` throws `OmnieDocumentError.appGroupUnavailable` when the entitlement is missing. `list()` throws `unsupportedContractVersion` when `contractVersion` is not `1` (`OmnieContract.version`).

Stable ids survive rename. The id is the string in `catalog.json`, not the file name.

### File Provider

Omnie-edit registers a File Provider domain:

- Identifier: `app.omnie.edit.documents`
- Display name: Omnie-edit

The extension is a read-only projection of the same catalog, so the Files app can browse unlocked files. Create, modify, and delete from Files are refused. omnie-ios should call `OmnieDocumentCatalog` rather than driving the File Provider.

The domain appears after a signed build has registered it. Until the app group exists, there is nothing for the provider to serve.

### What peers must not do in v1

- Write `catalog.json` or files under `OmnieEdit/Documents`.
- Read the app-private locked-file folder. It is not in the app group.
- Treat a missing file or a skipped catalog entry as permission to scan parent directories.

A later contract version can add an explicit write API. It should be a version bump, not a silent extra writer.

## Project layout

```text
Package.swift                  OmnieDocumentKit and OmnieEditCore
Sources/OmnieDocumentKit/      Shared read contract
Sources/OmnieEditCore/         Store, settings, lock policy, search, highlighter
OmnieEdit/                     SwiftUI app
OmnieFileProvider/             Read-only File Provider extension
Tests/OmnieEditCoreTests/      Unit tests
Contract/catalog.example.json  Fixture for the catalog schema
```

## Roadmap

- Folders, with a contract bump so `relativePath` may contain `/`.
- omnie-ios adopting `OmnieDocumentKit` for list and read.
- An explicit, versioned write path if a peer needs to create files.
- Richer find (regular expressions) and external-keyboard cursor commands.
- In-place editing of files that live outside the shared folder.

## Out of scope for v1

Cloud sync, collaboration, accounts, AI chat, analytics, Mac Catalyst, and App Store Connect or TestFlight wiring.

## TestFlight

TestFlight is in scope. `.github/workflows/testflight.yml` archives the **OmnieEdit** scheme and uploads it. The workflow runs on `workflow_dispatch` and on tags starting with `v`. It does not run on pull requests. The job uses the `xcode-27` runner. Secrets and portal steps are in `SIGNING.md`.

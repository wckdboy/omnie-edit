# Omnie Edit Privacy

Omnie Edit is designed around files the user explicitly selects.

- No account is required.
- No advertising or analytics SDK is included.
- The app does not upload document contents to an Omnie service.
- File contents remain in the locations selected in Files or iCloud Drive.
- `UserDefaults` stores editor preferences and security-scoped bookmark data for the recent-items list.
- Removing an item from Recents removes only its bookmark metadata; it does not delete the file or folder.
- Deleting an item inside the project browser changes the selected project on disk and always requires confirmation. Folder deletion also removes its contents.

Sharing a file, using an external storage provider, or later configuring a Git remote sends data only through the service the user chooses and is subject to that service's privacy terms.

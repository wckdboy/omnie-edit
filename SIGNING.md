# Signing and TestFlight

Team `XKA8CGC2AB`. `CODE_SIGN_STYLE` is Automatic on OmnieEdit, OmnieFileProvider, and OmnieEditTests, for Debug and Release. `DEVELOPMENT_TEAM` is `XKA8CGC2AB` on all six of those configurations.

| Target | Bundle ID |
| --- | --- |
| OmnieEdit | `ai.wckd.omnie.edit` |
| OmnieFileProvider | `ai.wckd.omnie.edit.fileprovider` |
| OmnieEditTests | `ai.wckd.omnie.edit.tests` |

Omnie iOS stays `ai.wckd.omnie` on the same team. The shared App Group stays `group.app.omnie.edit`.

No certificate, provisioning profile, or `.p8` belongs in this repository. `.gitignore` rejects `*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, and `*.provisionprofile`. Values live in Actions secrets.

## App Group for Omnie and Omnie Edit

`OmnieEdit/OmnieEdit.entitlements` requests `group.app.omnie.edit` for Debug and Release. `OmnieFileProvider/Debug.entitlements` and `OmnieFileProvider/Release.entitlements` request the same group. `OmnieFileProvider/Info.plist` sets `NSExtensionFileProviderDocumentGroup` to that group. Omnie (`ai.wckd.omnie`) reads `OmnieEdit/catalog.json` and `OmnieEdit/Documents/`. Omnie Edit is the writer.

Automatic signing does not create the group until each App ID allows it.

1. Apple Developer → Identifiers → App Groups, on team `XKA8CGC2AB`: register `group.app.omnie.edit` if it is not there yet.
2. App ID `ai.wckd.omnie` (Omnie): enable App Groups and include `group.app.omnie.edit`.
3. App ID `ai.wckd.omnie.edit` (Omnie Edit): enable App Groups and include `group.app.omnie.edit`.
4. App ID `ai.wckd.omnie.edit.fileprovider`: enable App Groups and include `group.app.omnie.edit`. Enable the production File Provider capability on this App ID when the portal asks for it.
5. In Xcode, leave `CODE_SIGN_ENTITLEMENTS` as committed. The app target uses `OmnieEdit/OmnieEdit.entitlements` for Debug and Release. The extension uses `OmnieFileProvider/Debug.entitlements` for Debug and `OmnieFileProvider/Release.entitlements` for Release.

Debug builds of the file provider include `com.apple.developer.fileprovider.testing-mode` so the domain can load before the account has the production File Provider capability. `OmnieFileProvider/Release.entitlements` omits that key. The TestFlight archive uses the Release configuration, so the uploaded extension does not carry testing mode.

`ai.wckd.omnie.edit.tests` is for local device tests. Archiving the `OmnieEdit` scheme uploads the app and the embedded file provider. It does not upload the test bundle.

The first launch after the profile includes the group creates the container. Until then, files stay in the app-private Application Support folder, and Settings says so.

## What CI does

`.github/workflows/testflight.yml` runs on `workflow_dispatch` and on tags that start with `v`. The job uses the `xcode-27` runner (arm64). It does not run on pull requests. `scripts/ci-testflight.sh` refuses to archive when `xcodebuild -version` is older than Xcode 27.

`scripts/ci-testflight.sh` then:

1. Checks the team, the three bundle IDs, the App Group on the app and both file-provider entitlement files, and that Release file-provider entitlements omit `com.apple.developer.fileprovider.testing-mode`.
2. Archives the `OmnieEdit` scheme, Release, destination `generic/platform=iOS`, with automatic signing for team `XKA8CGC2AB`.
3. Exports an App Store IPA with `ExportOptions.plist` (`method` `app-store-connect`, `signingStyle` `automatic`, `teamID` `XKA8CGC2AB`).
4. Uploads that archive to App Store Connect, which is what makes the build show up in TestFlight.

The build number sent to App Store Connect is `github.run_number` for this workflow (`CURRENT_PROJECT_VERSION`). The marketing version stays `MARKETING_VERSION` (`1.0`) in the Xcode project. App Store Connect rejects a second upload of the same build number. A re-run of a run that already uploaded needs a new run.

`OmnieEdit/Info.plist` keeps `ITSAppUsesNonExemptEncryption` false. The app has no network client and no analytics SDK. The workflow does not add either.

## Actions secrets

Set these for the repository that runs `.github/workflows/testflight.yml`. The names are the contract. The values are not written down here.

| Secret | What to store |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID of the App Store Connect API key. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from the App Store Connect API keys page. |
| `APP_STORE_CONNECT_API_KEY` | Full contents of the downloaded `.p8` file, including the `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines. A single line with `\n` between the PEM lines is accepted. |

The script writes the `.p8` under the runner temp directory for `xcodebuild -authenticationKeyPath` and removes it when the job exits. It does not print the key.

If any of the three values is missing, the TestFlight job fails.

## Outside this repository

The workflow does not create the Connect app, the App IDs, or the API key.

1. Apple Developer → Identifiers, team `XKA8CGC2AB`: App IDs `ai.wckd.omnie`, `ai.wckd.omnie.edit`, and `ai.wckd.omnie.edit.fileprovider`, each with App Group `group.app.omnie.edit`. The extension App ID needs the production File Provider capability. Leave testing mode off the distribution App ID. Automatic signing covers `ai.wckd.omnie.edit.tests` for local device runs.
2. App Store Connect → Apps: create the app for bundle ID `ai.wckd.omnie.edit` (name, SKU, primary language) when it is not there yet. The file provider ships inside that app. There is no separate Connect record for `ai.wckd.omnie.edit.fileprovider`.
3. App Store Connect → Users and Access → Integrations → App Store Connect API: create a key with the Admin or App Manager role so Xcode can sign and upload. Download the `.p8` once. Apple does not show it again. Copy the Key ID and the Issuer ID into the three secrets above.
4. Confirm this repository can schedule the `xcode-27` runner. Until that label is available, the workflow cannot start.
5. After an upload, wait for processing in App Store Connect. `ITSAppUsesNonExemptEncryption` is already false. Add internal testers on the TestFlight page. External testing still goes through Beta App Review in App Store Connect. This workflow does not submit that review.

## Local export

The same plist is what a local archive uses. Point `-authenticationKeyPath` at a `.p8` that is not in the tree:

```
xcodebuild archive -project OmnieEdit.xcodeproj -scheme OmnieEdit -configuration Release -destination 'generic/platform=iOS' -archivePath build/OmnieEdit.xcarchive -allowProvisioningUpdates -authenticationKeyPath /path/to/AuthKey.p8 -authenticationKeyID KEYID -authenticationKeyIssuerID ISSUER
xcodebuild -exportArchive -archivePath build/OmnieEdit.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath /path/to/AuthKey.p8 -authenticationKeyID KEYID -authenticationKeyIssuerID ISSUER
```

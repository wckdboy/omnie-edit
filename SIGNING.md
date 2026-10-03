# Signing and TestFlight

Team `XKA8CGC2AB`. The Xcode project keeps `CODE_SIGN_STYLE` Automatic on OmnieEdit, OmnieFileProvider, and OmnieEditTests, for Debug and Release, so a local run can use a development certificate. `DEVELOPMENT_TEAM` is `XKA8CGC2AB` on all six of those configurations.

TestFlight does not use that automatic path. `scripts/ci-testflight.sh` imports the Apple Distribution certificate and the two App Store profiles, then patches the OmnieEdit and OmnieFileProvider Release configurations to manual signing before it archives. The archive command passes only global `xcodebuild` settings. It does not pass `-authenticationKeyPath` or `-allowProvisioningUpdates`. The API key is used only for the `altool` upload.

| Target | Bundle ID | App Store profile |
| --- | --- | --- |
| OmnieEdit | `ai.wckd.omnie.edit` | `OmnieEdit AppStore CI` |
| OmnieFileProvider | `ai.wckd.omnie.edit.fileprovider` | `OmnieEditFP AppStore CI` |
| OmnieEditTests | `ai.wckd.omnie.edit.tests` | none (not archived) |

Omnie iOS stays `ai.wckd.omnie` on the same team.

No certificate, provisioning profile, or `.p8` belongs in this repository. `.gitignore` rejects `*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, and `*.provisionprofile`. Values live in Actions secrets.

## App Group

`group.app.omnie.edit` is registered on team `XKA8CGC2AB`, and the app plus both File Provider entitlement files request it. Builds signed by this team share the container with Omnie (`ai.wckd.omnie`) when that app also requests the same group.

The shared-folder contract is still `group.app.omnie.edit`. `Sources/OmnieDocumentKit/OmnieContract.swift` uses that identifier, and `OmnieFileProvider/Info.plist` sets `NSExtensionFileProviderDocumentGroup` to it. Omnie (`ai.wckd.omnie`) would read `OmnieEdit/catalog.json` and `OmnieEdit/Documents/` from that container. Omnie Edit is the writer. When the entitlement is missing, `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil and the editor keeps files in its private Application Support folder.

The App Store profiles `OmnieEdit AppStore CI` and `OmnieEditFP AppStore CI` must include `group.app.omnie.edit`. The release script validates the group before installing either profile. These files request the group:

- `OmnieEdit/OmnieEdit.entitlements` (Debug and Release for the app)
- `OmnieFileProvider/Debug.entitlements`
- `OmnieFileProvider/Release.entitlements`

Keep the group synchronized across both App IDs, both profiles, all three entitlement files, and Omnie itself. If any part is missing, signing or shared-container access fails instead of silently shipping a disconnected editor.

Debug builds of the file provider include `com.apple.developer.fileprovider.testing-mode` so the domain can load before the account has the production File Provider capability. `OmnieFileProvider/Release.entitlements` omits that key. The TestFlight archive uses the Release configuration, so the uploaded extension does not carry testing mode.

`ai.wckd.omnie.edit.tests` is for local device tests. Archiving the `OmnieEdit` scheme uploads the app and the embedded file provider. It does not upload the test bundle.

## What CI does

`.github/workflows/testflight.yml` runs on `workflow_dispatch` and on tags that start with `v`. The job uses the same `xcode-27-xlarge` runner as the main Omnie app. It does not run on pull requests. `scripts/ci-testflight.sh` refuses to archive when `xcodebuild -version` is older than Xcode 27.

`scripts/ci-testflight.sh` then:

1. Checks the team, the three bundle IDs, that the app and both file-provider entitlement files include `com.apple.security.application-groups` and `group.app.omnie.edit`, and that Release file-provider entitlements omit `com.apple.developer.fileprovider.testing-mode`.
2. Imports `IOS_DISTRIBUTION_P12_BASE64` into a temporary keychain as an Apple Distribution identity, then deletes that keychain on exit.
3. Installs `PROVISION_OMNIE_EDIT_BASE64` (`OmnieEdit AppStore CI`, `ai.wckd.omnie.edit`) and `PROVISION_OMNIE_EDIT_FP_BASE64` (`OmnieEditFP AppStore CI`, `ai.wckd.omnie.edit.fileprovider`). The script rejects a profile whose name, bundle id, or `group.app.omnie.edit` entitlement does not match.
4. Patches the OmnieEdit and OmnieFileProvider **Release** configurations in `project.pbxproj` to `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY` `Apple Distribution`, `CODE_SIGN_IDENTITY[sdk=iphoneos*]`, and `PROVISIONING_PROFILE_SPECIFIER` (`OmnieEdit AppStore CI` for the app, `OmnieEditFP AppStore CI` for the extension, including the `sdk=iphoneos*` specifier). Debug and OmnieEditTests stay Automatic. It then archives the `OmnieEdit` scheme, Release, destination `generic/platform=iOS`, passing only global settings: `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, `CODE_SIGN_IDENTITY[sdk=iphoneos*]`, `OTHER_CODE_SIGN_FLAGS` for the temporary keychain, and `CURRENT_PROJECT_VERSION`. There is no `Target:` prefix. The archive command does not pass `-allowProvisioningUpdates` or `-authenticationKeyPath`.
5. Exports an App Store IPA with `ExportOptions.plist` (`method` `app-store-connect`, `signingStyle` `manual`, `signingCertificate` `Apple Distribution`, `teamID` `XKA8CGC2AB`, and a `provisioningProfiles` map for both bundle IDs). The export command also has no App Store Connect authentication flags.
6. Uploads that IPA with `xcrun altool --upload-app` and the API key (`--apiKey` / `--apiIssuer`). The `.p8` is written where altool looks (`API_PRIVATE_KEYS_DIR` and `~/.appstoreconnect/private_keys`) and removed on exit. If this Xcode has no `altool`, the script uses `xcrun iTMSTransporter -m upload -assetFile` with the same key. It does not ask `xcodebuild -exportArchive` to upload.

The build number sent to App Store Connect is `github.run_number` for this workflow (`CURRENT_PROJECT_VERSION`). The marketing version stays `MARKETING_VERSION` (`1.0`) in the Xcode project. App Store Connect rejects a second upload of the same build number. A re-run of a run that already uploaded needs a new run.

`OmnieEdit/Info.plist` keeps `ITSAppUsesNonExemptEncryption` false. The app has no network client and no analytics SDK. The workflow does not add either.

## Actions secrets

Set these for the repository that runs `.github/workflows/testflight.yml`. The names are the contract. The values are not written down here.

| Secret | What to store |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of the Apple Distribution `.p12` for team `XKA8CGC2AB`. Whitespace is ignored. |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password for that `.p12`. |
| `PROVISION_OMNIE_EDIT_BASE64` | Base64 of the App Store profile named `OmnieEdit AppStore CI` for `ai.wckd.omnie.edit`, including `group.app.omnie.edit`. |
| `PROVISION_OMNIE_EDIT_FP_BASE64` | Base64 of the App Store profile named `OmnieEditFP AppStore CI` for `ai.wckd.omnie.edit.fileprovider`, including `group.app.omnie.edit`. |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID of the App Store Connect API key. Used only for the upload. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from the App Store Connect API keys page. Used only for the upload. |
| `APP_STORE_CONNECT_API_KEY` | Full contents of the downloaded `.p8` file, including the `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines. A single line with `\n` between the PEM lines is accepted. Used only for the upload. |

The script writes the `.p12`, the profiles, and the `.p8` under the runner temp directory (and the `.p8` in altool's private-keys directory) and removes them when the job exits. It does not print the key, the certificate password, or the profile bytes.

If any of these values is missing, the TestFlight job fails before it archives.

## Outside this repository

The workflow does not create the Connect app, the App IDs, the certificate, or the API key.

1. Apple Developer → Identifiers, team `XKA8CGC2AB`: App IDs `ai.wckd.omnie.edit` and `ai.wckd.omnie.edit.fileprovider`. Enable `group.app.omnie.edit` on both. The extension App ID also needs the production File Provider capability. Leave testing mode off the distribution App ID. Omnie (`ai.wckd.omnie`) needs the same group. Automatic signing still covers local device runs, including `ai.wckd.omnie.edit.tests`.
2. Apple Developer → Profiles: App Store profiles named `OmnieEdit AppStore CI` and `OmnieEditFP AppStore CI`, signed by the Apple Distribution certificate stored in `IOS_DISTRIBUTION_P12_BASE64`.
3. App Store Connect → Apps: create the app for bundle ID `ai.wckd.omnie.edit` (name, SKU, primary language) when it is not there yet. The file provider ships inside that app. There is no separate Connect record for `ai.wckd.omnie.edit.fileprovider`.
4. App Store Connect → Users and Access → Integrations → App Store Connect API: create a key with the Admin or App Manager role so altool can upload. Download the `.p8` once. Apple does not show it again. Copy the Key ID and the Issuer ID into the three upload secrets above. The archive does not use this key.
5. The workflow runs on `xcode-27-xlarge`.
6. After an upload, wait for processing in App Store Connect. `ITSAppUsesNonExemptEncryption` is already false. Add internal testers on the TestFlight page. External testing still goes through Beta App Review in App Store Connect. This workflow does not submit that review.

## Local export

Day-to-day runs stay on automatic signing in the Xcode project. The committed `ExportOptions.plist` is the manual TestFlight export: it expects the Apple Distribution identity and both profiles to be installed, and it does not contact App Store Connect. Use `scripts/ci-testflight.sh` on the `xcode-27-xlarge` runner for the upload. The script patches Release signing in the project for that archive and passes only global `xcodebuild` settings. Do not pass `-allowProvisioningUpdates` or `-authenticationKeyPath` to that archive, and do not pass `Target:`-prefixed signing settings; those per-target overrides are ignored and Xcode still asks for a Development profile.

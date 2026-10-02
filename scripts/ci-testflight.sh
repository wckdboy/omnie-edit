#!/usr/bin/env bash
# Archive Omnie-edit for the App Store and upload it to TestFlight.
#
# This is the signed release path. It fails when the runner or the App Store
# Connect API key is not ready. The app stays on-device: this script does not
# add a network client or an analytics SDK.
#
# Required environment (Actions secrets; see SIGNING.md):
#   APP_STORE_CONNECT_API_KEY_ID
#   APP_STORE_CONNECT_ISSUER_ID
#   APP_STORE_CONNECT_API_KEY     contents of the .p8
#   OMNIE_BUILD_NUMBER            integer CFBundleVersion for this upload
set -euo pipefail

cd "$(dirname "$0")/.."

team="XKA8CGC2AB"
key_path=""

fail() {
  echo "error: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "${name} is empty. Set it as an Actions secret. Names are listed in SIGNING.md."
  fi
}

cleanup() {
  if [[ -n "$key_path" && -f "$key_path" ]]; then
    rm -f "$key_path"
  fi
}
trap cleanup EXIT

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild is not installed. Run .github/workflows/testflight.yml on the xcode-27 runner."
fi

version_line="$(xcodebuild -version)"
version_line="${version_line%%$'\n'*}"
major="$(printf '%s\n' "$version_line" | awk '{ split($2, a, "."); print a[1] }')"
if [[ -z "$major" || "$major" -lt 27 ]]; then
  fail "Found ${version_line:-no Xcode version}. The TestFlight path needs Xcode 27. The xcode-27 runner label provides it."
fi
echo "Using ${version_line}"

require_env APP_STORE_CONNECT_API_KEY_ID
require_env APP_STORE_CONNECT_ISSUER_ID
require_env APP_STORE_CONNECT_API_KEY
require_env OMNIE_BUILD_NUMBER

if [[ ! "$OMNIE_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  fail "OMNIE_BUILD_NUMBER must be an integer (got a non-numeric value)."
fi
if [[ ! "$APP_STORE_CONNECT_API_KEY_ID" =~ ^[A-Za-z0-9]+$ ]]; then
  fail "APP_STORE_CONNECT_API_KEY_ID must be the alphanumeric Key ID from App Store Connect."
fi

team_hits="$(grep -c "DEVELOPMENT_TEAM = ${team};" OmnieEdit.xcodeproj/project.pbxproj || true)"
if [[ "$team_hits" -ne 6 ]]; then
  fail "Expected DEVELOPMENT_TEAM = ${team} on all six target configurations, found ${team_hits}."
fi
if ! grep -q "CODE_SIGN_STYLE = Automatic;" OmnieEdit.xcodeproj/project.pbxproj; then
  fail "OmnieEdit.xcodeproj is not set to automatic signing."
fi
for bundle in \
  "PRODUCT_BUNDLE_IDENTIFIER = ai.wckd.omnie.edit;" \
  "PRODUCT_BUNDLE_IDENTIFIER = ai.wckd.omnie.edit.fileprovider;" \
  "PRODUCT_BUNDLE_IDENTIFIER = ai.wckd.omnie.edit.tests;"
do
  hits="$(grep -c "$bundle" OmnieEdit.xcodeproj/project.pbxproj || true)"
  if [[ "$hits" -ne 2 ]]; then
    fail "Expected ${bundle} on Debug and Release, found ${hits}."
  fi
done
if grep -q "app\.omnie\.edit" OmnieEdit.xcodeproj/project.pbxproj; then
  fail "OmnieEdit.xcodeproj still contains an app.omnie.edit bundle identifier."
fi
if [[ ! -f ExportOptions.plist ]]; then
  fail "ExportOptions.plist is missing."
fi
if ! grep -q "<string>app-store-connect</string>" ExportOptions.plist; then
  fail "ExportOptions.plist method is not app-store-connect."
fi
if ! grep -q "<string>automatic</string>" ExportOptions.plist; then
  fail "ExportOptions.plist signingStyle is not automatic."
fi
if ! grep -q "<string>${team}</string>" ExportOptions.plist; then
  fail "ExportOptions.plist teamID is not ${team}."
fi
if [[ ! -f OmnieEdit.xcodeproj/xcshareddata/xcschemes/OmnieEdit.xcscheme ]]; then
  fail "Shared scheme OmnieEdit is missing."
fi

for entitlements in \
  OmnieEdit/OmnieEdit.entitlements \
  OmnieFileProvider/Debug.entitlements \
  OmnieFileProvider/Release.entitlements
do
  if ! grep -q "group.app.omnie.edit" "$entitlements"; then
    fail "${entitlements} is missing App Group group.app.omnie.edit."
  fi
done
if ! grep -q "com.apple.developer.fileprovider.testing-mode" OmnieFileProvider/Debug.entitlements; then
  fail "Debug File Provider entitlements are missing testing-mode."
fi
if grep -q "com.apple.developer.fileprovider.testing-mode" OmnieFileProvider/Release.entitlements; then
  fail "Release File Provider entitlements include com.apple.developer.fileprovider.testing-mode."
fi
if ! grep -A1 "ITSAppUsesNonExemptEncryption" OmnieEdit/Info.plist | grep -q "<false/>"; then
  fail "ITSAppUsesNonExemptEncryption must stay false."
fi

work="${RUNNER_TEMP:-/tmp}/omnie-edit-testflight"
rm -rf "$work"
mkdir -p "$work"
chmod 700 "$work"
key_path="${work}/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"

# A one-line secret paste stores the PEM newlines as the two characters \n.
umask 077
if [[ "$APP_STORE_CONNECT_API_KEY" != *$'\n'* && "$APP_STORE_CONNECT_API_KEY" == *'\n'* ]]; then
  printf '%b\n' "$APP_STORE_CONNECT_API_KEY" > "$key_path"
else
  printf '%s\n' "$APP_STORE_CONNECT_API_KEY" > "$key_path"
fi
chmod 600 "$key_path"

pem_header="$(head -n 1 "$key_path" | tr -d '\r')"
if [[ "$pem_header" != "-----BEGIN PRIVATE KEY-----" ]]; then
  fail "APP_STORE_CONNECT_API_KEY does not start with a PEM private key header."
fi

packages="${work}/SourcePackages"
archive="${work}/OmnieEdit.xcarchive"
export_dir="${work}/export"
upload_dir="${work}/upload"
upload_plist="${work}/ExportOptions-upload.plist"

echo "Resolving Swift packages"
xcodebuild -resolvePackageDependencies \
  -project OmnieEdit.xcodeproj \
  -scheme OmnieEdit \
  -clonedSourcePackagesDirPath "$packages"

echo "Archiving Release for generic/platform=iOS (build ${OMNIE_BUILD_NUMBER})"
xcodebuild archive \
  -project OmnieEdit.xcodeproj \
  -scheme OmnieEdit \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -clonedSourcePackagesDirPath "$packages" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$OMNIE_BUILD_NUMBER"

echo "Exporting App Store IPA"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportPath "$export_dir" \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

ipa=""
while IFS= read -r candidate; do
  ipa="$candidate"
  break
done < <(find "$export_dir" -name '*.ipa')
if [[ -z "$ipa" ]]; then
  fail "export did not produce an .ipa in ${export_dir}."
fi
echo "Exported $(basename "$ipa")"

# Copy before the upload so a rejected upload still leaves the IPA in the
# workspace for the artifact step. The committed plist stays on
# destination=export; the upload pass uses a temp copy.
artifact_dir="build/export"
rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"
cp "$ipa" "$artifact_dir/"

cp ExportOptions.plist "$upload_plist"
/usr/libexec/PlistBuddy -c 'Set :destination upload' "$upload_plist"

echo "Uploading to App Store Connect (TestFlight)"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportPath "$upload_dir" \
  -exportOptionsPlist "$upload_plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

echo "TestFlight upload submitted"

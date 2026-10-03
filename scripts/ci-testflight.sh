#!/usr/bin/env bash
# Archive Omnie-edit for the App Store and upload it to TestFlight.
#
# Omnie-edit deploys back to iOS 17, but its current SwiftUI toolbar code is
# compiled with the iOS 26 SDK. The workflow runs on macos-26, whose default
# Xcode includes that SDK.
#
# Signing is manual. Per-target xcodebuild settings (OmnieEdit:CODE_SIGN_*)
# are ignored, so Xcode still asks for a Development profile. Before the
# archive, this script writes the OmnieEdit and OmnieFileProvider Release
# configurations to Manual, Apple Distribution, CODE_SIGN_IDENTITY[sdk=iphoneos*],
# and the matching PROVISIONING_PROFILE_SPECIFIER. The archive command then
# passes only global settings. The script imports the Apple Distribution
# certificate and the two App Store profiles, does not pass
# -authenticationKeyPath or -allowProvisioningUpdates, and uploads the IPA
# with altool's API key.
#
# Required environment (Actions secrets; see SIGNING.md):
#   IOS_DISTRIBUTION_P12_BASE64
#   IOS_DISTRIBUTION_P12_PASSWORD
#   PROVISION_OMNIE_EDIT_BASE64       profile name "OmnieEdit AppStore CI"
#   PROVISION_OMNIE_EDIT_FP_BASE64    profile name "OmnieEditFP AppStore CI"
#   APP_STORE_CONNECT_API_KEY_ID      upload only
#   APP_STORE_CONNECT_ISSUER_ID       upload only
#   APP_STORE_CONNECT_API_KEY         upload only, contents of the .p8
#   OMNIE_BUILD_NUMBER                integer CFBundleVersion for this upload
set -euo pipefail

cd "$(dirname "$0")/.."

team="XKA8CGC2AB"
app_bundle="ai.wckd.omnie.edit"
extension_bundle="ai.wckd.omnie.edit.fileprovider"
app_profile_name="OmnieEdit AppStore CI"
extension_profile_name="OmnieEditFP AppStore CI"
identity="Apple Distribution"

key_path=""
home_key_path=""
p12_path=""
keychain=""
work=""
installed_profiles=()
previous_keychains=()

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
  if [[ -n "$home_key_path" && -f "$home_key_path" ]]; then
    rm -f "$home_key_path"
  fi
  if [[ -n "$p12_path" && -f "$p12_path" ]]; then
    rm -f "$p12_path"
  fi
  # ${array[@]} on an empty array is an unbound variable under macOS bash 3.2 with set -u.
  if [[ ${#installed_profiles[@]} -gt 0 ]]; then
    rm -f "${installed_profiles[@]}"
  fi
  if [[ -n "$keychain" ]]; then
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
  fi
  if [[ ${#previous_keychains[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${previous_keychains[@]}" >/dev/null 2>&1 || true
  fi
  if [[ -n "$work" && -d "$work" ]]; then
    rm -rf "${work}/private_keys" "${work}/profiles"
  fi
}
trap cleanup EXIT

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild is not installed. Run .github/workflows/testflight.yml on macos-26."
fi

version_line="$(xcodebuild -version)"
version_line="${version_line%%$'\n'*}"
major="$(printf '%s\n' "$version_line" | awk '{ split($2, a, "."); print a[1] }')"
if [[ -z "$major" || "$major" -lt 26 ]]; then
  fail "Found ${version_line:-no Xcode version}. Omnie-edit archives with Xcode 26 or later."
fi
echo "Using ${version_line}"

require_env IOS_DISTRIBUTION_P12_BASE64
require_env IOS_DISTRIBUTION_P12_PASSWORD
require_env PROVISION_OMNIE_EDIT_BASE64
require_env PROVISION_OMNIE_EDIT_FP_BASE64
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
  fail "OmnieEdit.xcodeproj should stay on automatic signing for local runs. The script switches OmnieEdit and OmnieFileProvider Release to manual before archive."
fi
for bundle in \
  "PRODUCT_BUNDLE_IDENTIFIER = ${app_bundle};" \
  "PRODUCT_BUNDLE_IDENTIFIER = ${extension_bundle};" \
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
if ! grep -q "<string>manual</string>" ExportOptions.plist; then
  fail "ExportOptions.plist signingStyle is not manual."
fi
if ! grep -q "<string>${identity}</string>" ExportOptions.plist; then
  fail "ExportOptions.plist signingCertificate is not ${identity}."
fi
if ! grep -q "<string>${team}</string>" ExportOptions.plist; then
  fail "ExportOptions.plist teamID is not ${team}."
fi
if ! grep -q "<key>${app_bundle}</key>" ExportOptions.plist; then
  fail "ExportOptions.plist provisioningProfiles is missing ${app_bundle}."
fi
if ! grep -q "<key>${extension_bundle}</key>" ExportOptions.plist; then
  fail "ExportOptions.plist provisioningProfiles is missing ${extension_bundle}."
fi
if ! grep -q "<string>${app_profile_name}</string>" ExportOptions.plist; then
  fail "ExportOptions.plist is missing profile ${app_profile_name}."
fi
if ! grep -q "<string>${extension_profile_name}</string>" ExportOptions.plist; then
  fail "ExportOptions.plist is missing profile ${extension_profile_name}."
fi
if [[ ! -f OmnieEdit.xcodeproj/xcshareddata/xcschemes/OmnieEdit.xcscheme ]]; then
  fail "Shared scheme OmnieEdit is missing."
fi

for entitlements in \
  OmnieEdit/OmnieEdit.entitlements \
  OmnieFileProvider/Debug.entitlements \
  OmnieFileProvider/Release.entitlements
do
  if ! grep -q "com.apple.security.application-groups" "$entitlements"; then
    fail "${entitlements} is missing com.apple.security.application-groups. OMNIE sharing requires it."
  fi
  if ! grep -q "group.app.omnie.edit" "$entitlements"; then
    fail "${entitlements} is missing group.app.omnie.edit. OMNIE sharing requires it."
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
p12_path="${work}/distribution.p12"
keychain="${work}/signing.keychain-db"

# macOS base64 decodes with -D. Strip whitespace so a wrapped secret still decodes.
decode_base64_to() {
  local dest="$1"
  local label="$2"
  tr -d '[:space:]' | base64 -D > "$dest"
  if [[ ! -s "$dest" ]]; then
    fail "${label} did not decode to a file."
  fi
}

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

printf '%s' "$IOS_DISTRIBUTION_P12_BASE64" | decode_base64_to "$p12_path" "IOS_DISTRIBUTION_P12_BASE64"
chmod 600 "$p12_path"

while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%\"}"
  line="${line#\"}"
  if [[ -n "$line" ]]; then
    previous_keychains+=("$line")
  fi
done < <(security list-keychains -d user)

keychain_password="$(openssl rand -base64 32)"
security delete-keychain "$keychain" >/dev/null 2>&1 || true
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
# -A lets Xcode's codesign (not only /usr/bin/codesign) read the key. The
# partition list limits that to codesign and the Apple tool partition.
security import "$p12_path" \
  -k "$keychain" \
  -P "$IOS_DISTRIBUTION_P12_PASSWORD" \
  -f pkcs12 \
  -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
if [[ ${#previous_keychains[@]} -gt 0 ]]; then
  security list-keychains -d user -s "$keychain" "${previous_keychains[@]}"
else
  security list-keychains -d user -s "$keychain"
fi

identities="$(security find-identity -v -p codesigning "$keychain")"
if ! printf '%s\n' "$identities" | grep -q "Apple Distribution"; then
  fail "The imported certificate is not an Apple Distribution identity."
fi
echo "Imported Apple Distribution identity into a temporary keychain"

install_profile() {
  local secret_name="$1"
  local expected_name="$2"
  local expected_bundle="$3"
  local raw="${work}/profiles/${expected_bundle}.mobileprovision"
  local decoded="${work}/profiles/${expected_bundle}.plist"
  mkdir -p "${work}/profiles"
  printf '%s' "${!secret_name}" | decode_base64_to "$raw" "$secret_name"
  if ! security cms -D -i "$raw" > "$decoded"; then
    fail "${secret_name} is not a provisioning profile."
  fi
  local name uuid app_id
  if ! name="$(plutil -extract Name raw -o - "$decoded" 2>/dev/null)"; then
    fail "${secret_name} has no Name."
  fi
  if ! uuid="$(plutil -extract UUID raw -o - "$decoded" 2>/dev/null)"; then
    fail "${secret_name} has no UUID."
  fi
  if ! app_id="$(plutil -extract Entitlements.application-identifier raw -o - "$decoded" 2>/dev/null)"; then
    fail "${secret_name} has no Entitlements.application-identifier."
  fi
  if [[ "$name" != "$expected_name" ]]; then
    fail "${secret_name} profile name is '${name}', expected '${expected_name}'."
  fi
  if [[ "$app_id" != "${team}.${expected_bundle}" ]]; then
    fail "${secret_name} application-identifier is '${app_id}', expected '${team}.${expected_bundle}'."
  fi
  if ! grep -q "group.app.omnie.edit" "$decoded"; then
    fail "${secret_name} does not entitle group.app.omnie.edit. Regenerate the profile with the OMNIE App Group."
  fi
  local profiles_dir="${HOME}/Library/MobileDevice/Provisioning Profiles"
  local dest="${profiles_dir}/${uuid}.mobileprovision"
  mkdir -p "$profiles_dir"
  cp "$raw" "$dest"
  installed_profiles+=("$dest")
  echo "Installed provisioning profile ${name} (${uuid}) for ${expected_bundle}"
}

install_profile PROVISION_OMNIE_EDIT_BASE64 "$app_profile_name" "$app_bundle"
install_profile PROVISION_OMNIE_EDIT_FP_BASE64 "$extension_profile_name" "$extension_bundle"

packages="${work}/SourcePackages"
archive="${work}/OmnieEdit.xcarchive"
export_dir="${work}/export"

echo "Resolving Swift packages"
xcodebuild -resolvePackageDependencies \
  -project OmnieEdit.xcodeproj \
  -scheme OmnieEdit \
  -clonedSourcePackagesDirPath "$packages"

# Per-target "OmnieEdit:CODE_SIGN_*" arguments are ignored and Xcode still
# requests a Development profile. Write the Release settings into the project
# instead. The archive below passes only global settings, so each target keeps
# the profile written here. No -allowProvisioningUpdates and no
# -authenticationKey* flags: the API key is for the altool upload only.
patch_release_signing() {
  local pbx="OmnieEdit.xcodeproj/project.pbxproj"
  python3 - "$pbx" "$app_bundle" "$app_profile_name" "$extension_bundle" "$extension_profile_name" "$identity" <<'PY'
import pathlib
import re
import sys

path, app_bundle, app_profile, extension_bundle, extension_profile, identity = sys.argv[1:]
profiles = {
    app_bundle: app_profile,
    extension_bundle: extension_profile,
}
text = pathlib.Path(path).read_text()
pattern = re.compile(
    r"\t\t[0-9A-F]+ /\* Release \*/ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"\t\t\tbuildSettings = \{.*?\n"
    r"\t\t\t\};\n"
    r"\t\t\tname = Release;\n"
    r"\t\t\};",
    re.DOTALL,
)
patched = {}

def replace_block(match):
    block = match.group(0)
    found = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", block)
    if not found:
        return block
    bundle = found.group(1).strip().strip('"')
    if bundle not in profiles:
        return block
    if block.count("CODE_SIGN_STYLE = Automatic;") != 1:
        raise SystemExit(f"error: Release configuration for {bundle} is not Automatic")
    if "PROVISIONING_PROFILE_SPECIFIER" in block or "CODE_SIGN_IDENTITY" in block:
        raise SystemExit(f"error: Release configuration for {bundle} already has manual signing settings")
    profile = profiles[bundle]
    setting = "\t" * 7
    lines = [
        f'{setting}CODE_SIGN_IDENTITY = "{identity}";',
        f'{setting}"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{identity}";',
        f"{setting}CODE_SIGN_STYLE = Manual;",
        f'{setting}PROVISIONING_PROFILE_SPECIFIER = "{profile}";',
        f'{setting}"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "{profile}";',
    ]
    replacement = "\n".join(lines) + "\n"
    block2, count = re.subn(r"\t+CODE_SIGN_STYLE = Automatic;\n", replacement, block, count=1)
    if count != 1:
        raise SystemExit(f"error: could not replace CODE_SIGN_STYLE for {bundle}")
    patched[bundle] = profile
    return block2

new_text, _ = pattern.subn(replace_block, text)
missing = [bundle for bundle in profiles if bundle not in patched]
if missing:
    raise SystemExit("error: did not patch Release signing for " + ", ".join(missing))
automatic = new_text.count("CODE_SIGN_STYLE = Automatic;")
manual = new_text.count("CODE_SIGN_STYLE = Manual;")
if automatic != 4 or manual != 2:
    raise SystemExit(
        f"error: expected 4 Automatic and 2 Manual CODE_SIGN_STYLE, found {automatic} and {manual}"
    )
pathlib.Path(path).write_text(new_text)
for bundle, profile in patched.items():
    print(f"Patched Release signing for {bundle} -> {profile}")
PY
}

echo "Archiving Release for generic/platform=iOS (build ${OMNIE_BUILD_NUMBER})"
patch_release_signing
xcodebuild archive \
  -project OmnieEdit.xcodeproj \
  -scheme OmnieEdit \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -clonedSourcePackagesDirPath "$packages" \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=${identity}" \
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]=${identity}" \
  "OTHER_CODE_SIGN_FLAGS=--keychain ${keychain}" \
  CURRENT_PROJECT_VERSION="$OMNIE_BUILD_NUMBER"

echo "Exporting App Store IPA"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportPath "$export_dir" \
  -exportOptionsPlist ExportOptions.plist

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
# workspace for the artifact step.
artifact_dir="build/export"
rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"
cp "$ipa" "$artifact_dir/"

keys_dir="${work}/private_keys"
mkdir -p "$keys_dir"
cp "$key_path" "${keys_dir}/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
chmod 600 "${keys_dir}/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
mkdir -p "${HOME}/.appstoreconnect/private_keys"
home_key_path="${HOME}/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
cp "$key_path" "$home_key_path"
chmod 600 "$home_key_path"
export API_PRIVATE_KEYS_DIR="$keys_dir"

echo "Uploading to App Store Connect (TestFlight)"
if xcrun --find altool >/dev/null 2>&1; then
  xcrun altool --upload-app \
    -f "$ipa" \
    -t ios \
    --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
elif xcrun --find iTMSTransporter >/dev/null 2>&1; then
  echo "altool is not in this Xcode. Uploading with iTMSTransporter -assetFile."
  xcrun iTMSTransporter \
    -m upload \
    -assetFile "$ipa" \
    -apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
    -apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
else
  fail "Neither altool nor iTMSTransporter is available to upload the IPA."
fi

echo "TestFlight upload submitted"

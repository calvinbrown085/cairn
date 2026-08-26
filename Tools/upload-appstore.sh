#!/bin/bash
# Archives Cairn and uploads it to App Store Connect, in one command:
#
#   Tools/upload-appstore.sh
#
# Uploading is not submitting. The build lands in App Store Connect and sits
# there; nothing reaches App Review until someone attaches it to a version and
# submits it in the web UI. Run this as often as you like.
#
# Two things about the signing setup are worth knowing before you read the
# code, because both cost real time the first time through:
#
# 1. The team ID is ZM4J56DC3Q, and it is NOT the string in the certificate
#    name. `security find-identity` prints identities as
#    "Apple Development: Calvin Brown (VE8UL5JBLS)" — that parenthesized value
#    is the *person* ID, not the team. Passing it as `teamID` fails with the
#    thoroughly misleading "No Account for Team ... / No profiles for
#    com.calvinbrown.Cairn were found", which reads like a missing Xcode
#    account rather than a wrong team. The authoritative value is
#    DEVELOPMENT_TEAM in project.yml, which invariant X7 pins.
#
# 2. There is no Apple Distribution certificate in the keychain up front, and
#    there does not need to be. `-allowProvisioningUpdates` has Xcode mint the
#    distribution certificate and the App Store profile on demand, using the
#    Apple ID session that Xcode.app holds. That session is the one credential
#    this script cannot create for itself: if Xcode is signed out, every step
#    below fails at export, and the fix is to sign back in under
#    Xcode > Settings > Accounts.
#
# `destination: upload` in the export options is what makes the upload reuse
# that same Xcode session. The alternative — exporting an .ipa and pushing it
# with `xcrun altool` — needs an App Store Connect API key (a .p8 in
# ~/.appstoreconnect/private_keys/) that this machine does not have. If you
# ever want unattended uploads from CI, that key is the thing to create.
#
# Build numbers are not managed here: `manageAppVersionAndBuildNumber` is
# false so that what ships is exactly what project.yml says. App Store Connect
# rejects a build number it has already seen, so bump
# CURRENT_PROJECT_VERSION in project.yml before re-uploading the same
# MARKETING_VERSION.

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="$(grep -m1 'DEVELOPMENT_TEAM:' project.yml | awk '{print $2}')"
if [ -z "$TEAM_ID" ]; then
  echo "error: no DEVELOPMENT_TEAM in project.yml" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ARCHIVE="$WORK/Cairn.xcarchive"
OPTIONS="$WORK/ExportOptions.plist"

# An archive is built from the working tree, not from HEAD, so a dirty tree
# ships uncommitted code under a version number that claims to be a commit.
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty; commit or stash before uploading" >&2
  git status --short >&2
  exit 1
fi

echo "==> Verifying (tests, build, invariants)"
.claude/factory/bin/verify.sh

echo "==> Generating project"
xcodegen generate

echo "==> Archiving"
xcodebuild archive \
  -project Cairn.xcodeproj \
  -scheme Cairn \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates

VERSION="$(plutil -extract CFBundleShortVersionString raw \
  "$ARCHIVE/Products/Applications/Cairn.app/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw \
  "$ARCHIVE/Products/Applications/Cairn.app/Info.plist")"
echo "==> Archived Cairnfield $VERSION ($BUILD) from $(git rev-parse --short HEAD)"

cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>destination</key><string>upload</string>
</dict></plist>
PLIST

echo "==> Uploading to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$WORK/out" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates

echo
echo "Uploaded Cairnfield $VERSION ($BUILD)."
echo "It processes for 10-30 minutes before it appears in TestFlight or is"
echo "selectable on a version. Nothing has been submitted for review."

#!/bin/bash
set -euo pipefail

VERSION="${1:?usage: release.sh <version> (e.g. 1.0.0)}"
IDENTITY="${IDENTITY:-Developer ID Application}"
TEAM_ID="${TEAM_ID:-XSXSZ2A7D9}"
NOTARY_PROFILE="${NOTARY_PROFILE:-personalisland-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/release"
APP="$DD/Build/Products/Release/PersonalIsland.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/PersonalIsland-$VERSION.dmg"
SPARKLE_BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "ERROR: no 'Developer ID Application' certificate in keychain."
  echo "Create it: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
  exit 1
fi

cd "$ROOT"
plutil -replace CFBundleShortVersionString -string "$VERSION" Support/Info.plist
xcodegen
xcodebuild -project PersonalIsland.xcodeproj -scheme PersonalIsland \
  -configuration Release -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build

codesign --force --sign "$IDENTITY" --timestamp --options=runtime \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign "$IDENTITY" --timestamp --options=runtime \
  --entitlements "$ROOT/Support/PersonalIsland.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "== signed OK =="

rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "PersonalIsland" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "== notarizing (this takes a few minutes) =="
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

if [ -x "$SPARKLE_BIN/sign_update" ]; then
  echo "== sparkle signature for appcast =="
  "$SPARKLE_BIN/sign_update" "$DMG"
else
  echo "WARN: sparkle sign_update not found at $SPARKLE_BIN"
fi

echo ""
echo "DONE: $DMG"
echo "Next: update appcast.xml with the version/signature above, commit it, then:"
echo "  gh release create v$VERSION \"$DMG\" --title \"PersonalIsland $VERSION\" --notes \"...\""

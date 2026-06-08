#!/usr/bin/env bash
set -euo pipefail

# Load secrets
source <(grep -v '^#' secrets.yml | sed 's/: /=/' | sed 's/^/export /' | sed 's/"//g')

VERSION="${1:-1.0.0}"
APP_NAME="Brace"
BUNDLE_ID="com.fagundes.brace"
REPO="FagundesCristianoF/json-viewer"
DERIVED="JsonViewApp/build/DerivedData"
APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
DMG_PATH="${APP_NAME}-${VERSION}.dmg"

echo "==> Building Rust FFI (release)"
cargo build --release -p jsonview-ffi

echo "==> Building $APP_NAME $VERSION (Release)"
cd JsonViewApp
xcodebuild \
  -project Brace.xcodeproj \
  -scheme Brace \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM=VP83767PVX \
  CODE_SIGN_STYLE=Automatic \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
cd ..

echo "==> Notarizing"
ditto -c -k --keepParent "$APP_PATH" /tmp/brace-notarize.zip
xcrun notarytool submit /tmp/brace-notarize.zip \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
rm /tmp/brace-notarize.zip

echo "==> Stapling"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Creating DMG"
STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$STAGING"

echo "==> SHA256"
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "sha256: $SHA"

echo "==> Creating GitHub release v$VERSION"
gh release create "v$VERSION" "$DMG_PATH" \
  --title "$APP_NAME v$VERSION" \
  --notes "Brace v$VERSION — native macOS JSON editor and HTTP scanner." \
  --repo "$REPO"

echo "==> Updating cask"
sed -i '' \
  -e "s|version \".*\"|version \"$VERSION\"|" \
  -e "s|sha256 \".*\"|sha256 \"$SHA\"|" \
  homebrew/brace.rb

git add homebrew/brace.rb
git commit -m "chore: bump cask to v$VERSION"
git push origin HEAD:master

echo ""
echo "Done! Install with:"
echo "  brew install --cask $APP_NAME"

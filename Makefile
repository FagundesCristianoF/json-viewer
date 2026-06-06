## Json Viewer — release, sign, notarize, package
##
## Required env vars for signing/notarization:
##   APPLE_TEAM_ID        — your 10-char Apple Team ID
##   APPLE_IDENTITY       — codesign identity, e.g. "Developer ID Application: Name (TEAMID)"
##   APPLE_ID             — Apple ID email for notarytool
##   APPLE_APP_PASSWORD   — app-specific password for notarytool
##   APPLE_KEYCHAIN_PROFILE — notarytool stored-credentials profile name (optional)

APP_NAME   := Json Viewer
BUNDLE_ID  := com.fagundes.jsonview
BIN        := jsonview
VERSION    := $(shell grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)"/\1/')
APP_BUNDLE := target/release/bundle/osx/$(APP_NAME).app
DMG_NAME   := JsonViewer-$(VERSION).dmg
DMG_PATH   := target/release/$(DMG_NAME)

.PHONY: build bundle sign notarize staple dmg all clean

## Step 1: Compile release binary
build:
	cargo build --release

## Step 2: Create .app bundle (requires cargo-bundle: cargo install cargo-bundle)
bundle: build
	cargo bundle --release

## Step 3: Sign the .app with hardened runtime (required for notarization)
sign: bundle
	codesign --deep --force --options runtime \
		--entitlements assets/entitlements.plist \
		--sign "$(APPLE_IDENTITY)" \
		"$(APP_BUNDLE)"
	codesign --verify --deep --strict "$(APP_BUNDLE)"
	@echo "Signed: $(APP_BUNDLE)"

## Step 4: Submit for notarization
notarize: sign
	ditto -c -k --keepParent "$(APP_BUNDLE)" /tmp/$(BIN)-notarize.zip
	xcrun notarytool submit /tmp/$(BIN)-notarize.zip \
		--apple-id "$(APPLE_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--wait
	rm /tmp/$(BIN)-notarize.zip

## Step 5: Staple the notarization ticket
staple:
	xcrun stapler staple "$(APP_BUNDLE)"
	xcrun stapler validate "$(APP_BUNDLE)"

## Step 6: Create distributable DMG
dmg: staple
	mkdir -p target/release/dmg-stage
	cp -R "$(APP_BUNDLE)" target/release/dmg-stage/
	ln -sf /Applications target/release/dmg-stage/Applications
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder target/release/dmg-stage \
		-ov -format UDZO \
		"$(DMG_PATH)"
	rm -rf target/release/dmg-stage
	@echo "DMG ready: $(DMG_PATH)"

## Full pipeline: build → bundle → sign → notarize → staple → dmg
all: dmg
	@echo "Release complete: $(DMG_PATH)"

## Generate SHA256 for Homebrew formula (run after 'make dmg')
brew-sha:
	shasum -a 256 "$(DMG_PATH)"

clean:
	cargo clean

## ──────────────────────────────────────────────
## Store notarytool credentials (one-time setup):
##   xcrun notarytool store-credentials PROFILE_NAME \
##     --apple-id YOU@EXAMPLE.COM \
##     --team-id TEAMID \
##     --password APP_SPECIFIC_PASSWORD
## ──────────────────────────────────────────────

## DevKit — build, sign, notarize, package
## Secrets are loaded from secrets.yml (gitignored).

APP_NAME    := DevKit
BUNDLE_ID   := com.fagundes.devkit
VERSION     := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" JsonViewApp/JsonViewApp/Info.plist)
DERIVED     := JsonViewApp/build/DerivedData
APP_BUNDLE  := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
DMG_NAME    := $(APP_NAME)-$(VERSION).dmg
DMG_PATH    := $(DMG_NAME)

# Load secrets.yml → env vars
-include secrets.mk
secrets.mk: secrets.yml
	@grep -v '^#' secrets.yml | sed 's/: /=/' | sed 's/"//g' > $@

.PHONY: ffi build sign notarize staple dmg publish clean

## Build Rust FFI library
ffi:
	cargo build --release -p jsonview-ffi

## Build DevKit.app (Release)
build: ffi
	cd JsonViewApp && xcodebuild \
		-project DevKit.xcodeproj \
		-scheme DevKit \
		-configuration Release \
		-destination "platform=macOS" \
		-derivedDataPath build/DerivedData \
		DEVELOPMENT_TEAM=VP83767PVX \
		CODE_SIGN_STYLE=Automatic \
		build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

## Notarize the built app
notarize: build
	ditto -c -k --keepParent "$(APP_BUNDLE)" /tmp/devkit-notarize.zip
	xcrun notarytool submit /tmp/devkit-notarize.zip \
		--apple-id "$(APPLE_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--wait
	rm /tmp/devkit-notarize.zip

## Staple notarization ticket
staple: notarize
	xcrun stapler staple "$(APP_BUNDLE)"
	xcrun stapler validate "$(APP_BUNDLE)"

## Create DMG
dmg: staple
	$(eval STAGING := $(shell mktemp -d))
	cp -R "$(APP_BUNDLE)" "$(STAGING)/"
	ln -sf /Applications "$(STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder "$(STAGING)" \
		-ov -format UDZO \
		"$(DMG_PATH)"
	rm -rf "$(STAGING)"
	@echo "DMG: $(DMG_PATH)"
	@echo "SHA256: $$(shasum -a 256 $(DMG_PATH) | awk '{print $$1}')"

## Full pipeline + GitHub release + cask update
publish: dmg
	bash scripts/publish.sh $(VERSION)

## Print SHA256 of the DMG (run after dmg)
brew-sha:
	shasum -a 256 "$(DMG_PATH)"

clean:
	cargo clean
	rm -rf JsonViewApp/build secrets.mk

APP_NAME = Clonk
BUNDLE   = build/$(APP_NAME).app
DMG      = build/$(APP_NAME).dmg
BIN      = .build/release/$(APP_NAME)
ICONSET  = build/AppIcon.iconset
ICNS     = Resources/AppIcon.icns
ENTITLEMENTS     = Resources/Clonk.entitlements
MAS_ENTITLEMENTS = Resources/Clonk.mas.entitlements
MAS_PKG          = build/$(APP_NAME).pkg
MAS_PROFILE      ?= Resources/Clonk_MAS.provisionprofile

# Set these to your Apple distribution identities before running build-mas.
# Find them with: security find-identity -v -p codesigning
MAS_SIGN_APP ?= 3rd Party Mac Developer Application: William Whitehouse (8248296AJX)
MAS_SIGN_PKG ?= 3rd Party Mac Developer Installer: William Whitehouse (8248296AJX)

# Developer ID identity for direct-distribution (website / DMG) builds. This
# is different from the MAS identity above — Gatekeeper requires Developer ID
# Application signing + notarization for download-and-run binaries.
DEVID_SIGN_APP ?= Developer ID Application: William Whitehouse (8248296AJX)

# App Store Connect API key for notarytool. The .p8 lives outside the repo;
# memory: KZ765P9ZHP / issuer 66eec4bc-6987-480b-9af2-c26ea01d2ed2.
NOTARY_KEY_ID  ?= KZ765P9ZHP
NOTARY_ISSUER  ?= 66eec4bc-6987-480b-9af2-c26ea01d2ed2
NOTARY_KEY     ?= $(HOME)/.appstoreconnect/private_keys/AuthKey_$(NOTARY_KEY_ID).p8

# Stable signing identity so macOS keeps the Accessibility/TCC grant (the
# keyboard event tap) across rebuilds. Falls back to ad-hoc ("-") on machines
# without the self-signed "Clonk Dev" cert. Create one once via Keychain Access
# → Certificate Assistant → Create a Certificate → type "Code Signing".
SIGN_ID := $(shell security find-certificate -c "Clonk Dev" >/dev/null 2>&1 && echo "Clonk Dev" || echo -)

APPBIN ?= ../app-arently/.build/release/app-arently

.PHONY: all build icon app run dmg build-mas bump version clean screenshot test dist dist-manifest

all: app

build:
	swift build -c release

icon: build
	rm -rf $(ICONSET)
	$(BIN) --icon $(ICONSET)
	@if command -v pngquant >/dev/null 2>&1; then \
		echo "Quantizing icon PNGs..."; \
		for f in $(ICONSET)/*.png; do \
			pngquant --quality=90-100 --speed 1 --force --output "$$f" "$$f" || true; \
		done; \
	else \
		echo "pngquant not found, skipping quantization (brew install pngquant)"; \
	fi
	@if command -v optipng >/dev/null 2>&1; then \
		echo "Optimizing icon PNGs..."; \
		optipng -quiet -o7 $(ICONSET)/*.png; \
	else \
		echo "optipng not found, skipping PNG optimization (brew install optipng)"; \
	fi
	iconutil -c icns $(ICONSET) -o $(ICNS)
	@echo "Icon -> $(ICNS)"

app: icon
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	strip $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(ICNS) $(BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --deep --sign "$(SIGN_ID)" --entitlements $(ENTITLEMENTS) $(BUNDLE)
	@echo "Built $(BUNDLE) (signed: $(SIGN_ID))"

run: app
	open $(BUNDLE)

# Package the signed .app into a compressed, drag-to-install disk image.
dmg: app
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(BUNDLE) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/dmg -ov -format UDZO $(DMG)
	rm -rf build/dmg
	@echo "Built $(DMG)"

# Print the current marketing + build version.
version:
	@SHORT=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
	BUILD=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist); \
	echo "Clonk $$SHORT ($$BUILD)"

# Increment CFBundleVersion by 1. App Store Connect rejects duplicate build
# numbers under the same marketing version, so build-mas calls this first to
# guarantee each submission is fresh.
bump:
	@CURRENT=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist); \
	NEXT=$$(( CURRENT + 1 )); \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$NEXT" Resources/Info.plist; \
	echo "CFBundleVersion: $$CURRENT -> $$NEXT"

# Mac App Store distribution package.
# Requires "3rd Party Mac Developer Application" and "3rd Party Mac Developer
# Installer" certificates from your Apple Developer account. Override the
# signing identities via MAS_SIGN_APP and MAS_SIGN_PKG env vars.
# Bumps CFBundleVersion automatically; pass NO_BUMP=1 to skip.
build-mas: icon
	@if [ -z "$(NO_BUMP)" ]; then $(MAKE) --no-print-directory bump; fi
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	strip $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(ICNS) $(BUNDLE)/Contents/Resources/AppIcon.icns
	cp Resources/PrivacyInfo.xcprivacy $(BUNDLE)/Contents/Resources/PrivacyInfo.xcprivacy
	cp $(MAS_PROFILE) $(BUNDLE)/Contents/embedded.provisionprofile
	xattr -cr $(BUNDLE)
	codesign --force --deep \
		--sign "$(MAS_SIGN_APP)" \
		--identifier ltd.anti.clonk \
		--entitlements $(MAS_ENTITLEMENTS) \
		--options runtime \
		$(BUNDLE)
	productbuild \
		--component $(BUNDLE) /Applications \
		--sign "$(MAS_SIGN_PKG)" \
		$(MAS_PKG)
	@echo "Built $(MAS_PKG)"
	@echo "Upload: xcrun altool --upload-package $(MAS_PKG) --type osx --apiKey <key> --apiIssuer <issuer>"

screenshot: app
	$(APPBIN) profile --app "$(BUNDLE)" --out Resources/benchmark.png
	@echo "Screenshot: Resources/benchmark.png"

test:
	swift test

# ──────────────────────────────────────────────────────────────────────────
# Direct-distribution (website / DMG) build.
#
# Builds a Developer ID-signed, hardened-runtime, notarized, stapled DMG
# ready to upload to R2 for paid customers. This is the *non-MAS* path:
# Gatekeeper requires Developer ID + notarization for download-and-run apps,
# distinct from the MAS pipeline above which uses 3rd Party Mac Developer.
#
# Outputs:
#   build/Clonk-<version>.dmg   — notarized + stapled, customer-facing
#   build/Clonk-<version>.json  — version manifest for binaries/<app>.json
#
# The Clonk Dev local-signing convenience does NOT apply here — Developer ID
# is the only identity macOS will trust outside the App Store.
DIST_VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DIST_DMG     = build/Clonk-$(DIST_VERSION).dmg
DIST_JSON    = build/Clonk-$(DIST_VERSION).json

dist: icon
	@echo "── Direct-distribution build: Clonk $(DIST_VERSION) ──"
	rm -rf $(BUNDLE) $(DIST_DMG) $(DIST_JSON)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	strip $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(ICNS) $(BUNDLE)/Contents/Resources/AppIcon.icns
	cp Resources/PrivacyInfo.xcprivacy $(BUNDLE)/Contents/Resources/PrivacyInfo.xcprivacy
	xattr -cr $(BUNDLE)
	@echo "── Signing with Developer ID + hardened runtime ──"
	codesign --force --deep --timestamp \
		--sign "$(DEVID_SIGN_APP)" \
		--options runtime \
		--entitlements $(ENTITLEMENTS) \
		$(BUNDLE)
	codesign --verify --strict --deep --verbose=2 $(BUNDLE)
	@echo "── Building DMG ──"
	rm -rf build/dmg
	mkdir -p build/dmg
	cp -R $(BUNDLE) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/dmg -ov -format UDZO $(DIST_DMG)
	rm -rf build/dmg
	@echo "── Submitting to Apple notary service (may take a few minutes) ──"
	xcrun notarytool submit $(DIST_DMG) \
		--key $(NOTARY_KEY) \
		--key-id $(NOTARY_KEY_ID) \
		--issuer $(NOTARY_ISSUER) \
		--wait
	@echo "── Stapling notarization ticket ──"
	xcrun stapler staple $(DIST_DMG)
	xcrun stapler validate $(DIST_DMG)
	spctl --assess --type open --context context:primary-signature --verbose=2 $(DIST_DMG) || true
	@echo "── Writing version manifest ──"
	$(MAKE) --no-print-directory dist-manifest
	@echo ""
	@echo "✓ Built $(DIST_DMG)"
	@echo "✓ Manifest $(DIST_JSON)"
	@echo ""
	@echo "Upload to anti-ltd-binaries:"
	@echo "  wrangler r2 object put anti-ltd-binaries/binaries/clonk.dmg  --file $(DIST_DMG)"
	@echo "  wrangler r2 object put anti-ltd-binaries/binaries/clonk.json --file $(DIST_JSON) --content-type application/json"

# Emits the binaries/clonk.json that the website serves at /api/version.
# Shape per anti-ltd/src/worker/versions.js: version + optional metadata; the
# Worker adds `app` and `downloadUrl` at response time.
dist-manifest:
	@SIZE=$$(stat -f %z $(DIST_DMG)); \
	SHA=$$(shasum -a 256 $(DIST_DMG) | awk '{print $$1}'); \
	RELEASED=$$(date -u +"%Y-%m-%dT%H:%M:%SZ"); \
	MIN_OS=$$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist); \
	NOTES=$${CLONK_RELEASE_NOTES:-"Initial release."}; \
	printf '{\n  "version": "%s",\n  "releasedAt": "%s",\n  "notes": "%s",\n  "minOS": "macOS %s",\n  "sha256": "%s",\n  "size": %d\n}\n' \
		"$(DIST_VERSION)" "$$RELEASED" "$$NOTES" "$$MIN_OS" "$$SHA" "$$SIZE" \
		> $(DIST_JSON)
	@echo "  version  $(DIST_VERSION)"
	@echo "  sha256   $$(shasum -a 256 $(DIST_DMG) | awk '{print $$1}')"
	@echo "  size     $$(stat -f %z $(DIST_DMG)) bytes"

clean:
	rm -rf .build build

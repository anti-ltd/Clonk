APP_NAME = Clonk
BUNDLE   = build/$(APP_NAME).app
DMG      = build/$(APP_NAME).dmg
BIN      = .build/release/$(APP_NAME)
ICONSET  = build/AppIcon.iconset
ICNS     = Resources/AppIcon.icns
ENTITLEMENTS     = Resources/Clonk.entitlements
MAS_ENTITLEMENTS = Resources/Clonk.mas.entitlements
MAS_PKG          = build/$(APP_NAME).pkg

# Set these to your Apple distribution identities before running build-mas.
# Find them with: security find-identity -v -p codesigning
MAS_SIGN_APP ?= 3rd Party Mac Developer Application: $(shell git config user.name)
MAS_SIGN_PKG ?= 3rd Party Mac Developer Installer: $(shell git config user.name)

# Stable signing identity so macOS keeps the Accessibility/TCC grant (the
# keyboard event tap) across rebuilds. Falls back to ad-hoc ("-") on machines
# without the self-signed "Clonk Dev" cert. Create one once via Keychain Access
# → Certificate Assistant → Create a Certificate → type "Code Signing".
SIGN_ID := $(shell security find-certificate -c "Clonk Dev" >/dev/null 2>&1 && echo "Clonk Dev" || echo -)

APPBIN ?= ../app-arently/.build/release/app-arently

.PHONY: all build icon app run dmg build-mas clean screenshot

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

# Mac App Store distribution package.
# Requires "3rd Party Mac Developer Application" and "3rd Party Mac Developer
# Installer" certificates from your Apple Developer account. Override the
# signing identities via MAS_SIGN_APP and MAS_SIGN_PKG env vars.
build-mas: icon
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	strip $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(ICNS) $(BUNDLE)/Contents/Resources/AppIcon.icns
	cp Resources/PrivacyInfo.xcprivacy $(BUNDLE)/Contents/Resources/PrivacyInfo.xcprivacy
	codesign --force --deep \
		--sign "$(MAS_SIGN_APP)" \
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
	@mkdir -p assets
	$(APPBIN) profile --app "$(BUNDLE)" --out assets/benchmark.png
	@echo "Screenshot: assets/benchmark.png"

clean:
	rm -rf .build build

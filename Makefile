APP_NAME = Clonk
BUNDLE   = build/$(APP_NAME).app
BIN      = .build/release/$(APP_NAME)
ICONSET  = build/AppIcon.iconset
ICNS     = Resources/AppIcon.icns

.PHONY: all build icon app run clean

all: app

build:
	swift build -c release

icon: build
	rm -rf $(ICONSET)
	$(BIN) --icon $(ICONSET)
	@if command -v pngquant >/dev/null 2>&1; then \
		echo "Quantizing icon PNGs..."; \
		for f in $(ICONSET)/*.png; do \
			pngquant --quality=65-90 --speed 1 --force --output "$$f" "$$f"; \
		done; \
	else \
		echo "pngquant not found, skipping quantization (brew install pngquant)"; \
	fi
	@if command -v optipng >/dev/null 2>&1; then \
		echo "Optimizing icon PNGs..."; \
		optipng -quiet -o2 $(ICONSET)/*.png; \
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
	codesign --force --deep --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: app
	open $(BUNDLE)

clean:
	rm -rf .build build

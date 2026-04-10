APP     = Cogito.app
BINARY  = .build/arm64-apple-macosx/debug/Cogito
MACOS   = $(APP)/Contents/MacOS
PLIST   = $(APP)/Contents/Info.plist

.PHONY: build bundle run clean

build:
	swift build

bundle: build
	mkdir -p $(MACOS)
	/bin/cp $(BINARY) $(MACOS)/Cogito
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
  <key>CFBundleExecutable</key><string>Cogito</string>\n\
  <key>CFBundleIdentifier</key><string>com.cogito.app</string>\n\
  <key>CFBundleName</key><string>Cogito</string>\n\
  <key>CFBundlePackageType</key><string>APPL</string>\n\
  <key>CFBundleShortVersionString</key><string>1.0</string>\n\
  <key>LSMinimumSystemVersion</key><string>14.0</string>\n\
  <key>NSHighResolutionCapable</key><true/>\n\
  <key>NSPrincipalClass</key><string>NSApplication</string>\n\
</dict></plist>\n' > $(PLIST)

run: bundle
	codesign --force --deep --sign - $(APP)
	pkill -x Cogito 2>/dev/null || true
	open $(APP)

clean:
	rm -rf $(APP) .build

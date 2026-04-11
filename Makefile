APP     = Cogito.app
BINARY  = .build/arm64-apple-macosx/debug/Cogito
MACOS   = $(APP)/Contents/MacOS
PLIST   = $(APP)/Contents/Info.plist
# Python MLX ships a pre-compiled metallib compatible with mlx-swift 0.31.x.
# SPM does not compile .metal shaders, so we copy it here.
MLX_METALLIB = $(shell python3 -c "import mlx.core as mx, os; print(os.path.dirname(mx.__spec__.origin))" 2>/dev/null)/lib/mlx.metallib

.PHONY: build bundle run clean

build:
	swift build

bundle: build
	@python3 -c "import notebooklm" 2>/dev/null || (echo "Installing notebooklm-py..."; pip3 install --quiet notebooklm-py)
	mkdir -p $(MACOS)
	mkdir -p $(APP)/Contents/Resources/Scripts
	/bin/cp $(BINARY) $(MACOS)/Cogito
	/bin/cp Scripts/generate_video.py $(APP)/Contents/Resources/Scripts/
	@if [ -f "$(MLX_METALLIB)" ]; then \
		/bin/cp $(MLX_METALLIB) $(MACOS)/mlx.metallib; \
		echo "Copied mlx.metallib from Python MLX."; \
	else \
		echo "Warning: mlx.metallib not found. GPU inference will fail."; \
		echo "Install with: pip3 install mlx"; \
	fi
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

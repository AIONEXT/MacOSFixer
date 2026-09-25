# MacOSFixer Makefile

.PHONY: build test run clean install uninstall release lint format \
	bump-version sign notarize dmg-release

# Build configuration
BUILD_CONFIG = release
TARGET = macosfixer
BUILD_DIR = .build/$(BUILD_CONFIG)
BINARY = $(BUILD_DIR)/$(TARGET)

# Version: single source of truth is VERSION (see `make bump-version`)
VERSION = $(shell python3 Version.py)
DMG_NAME = MacOSFixer-1.0.0.dmg

# Swift configuration
SWIFT = swift
# --disable-sandbox: required when building in sandboxes/CI containers where sandbox-exec is unavailable
SWIFTFLAGS = -c $(BUILD_CONFIG) --disable-sandbox
PACKAGE = Package.swift

# Code signing identity (empty = ad-hoc). Set to your Developer ID:
#   make SIGN_ID="Developer ID Application: Your Name (TEAM_ID)" sign
SIGN_ID ?= -
# Apple ID for notarization (make NOTARY_EMAIL=... overrides)
NOTARY_EMAIL ?=
APP_PASSWORD ?=

# Default target
all: build

# Build the project
build:
	@echo "🔨 Building $(TARGET)..."
	$(SWIFT) build $(SWIFTFLAGS)
	@echo "✅ Build complete: $(BINARY)"

# Build debug version
build-debug:
	@echo "🔨 Building $(TARGET) (debug)..."
	$(SWIFT) build -c debug

# Run tests
test:
	@echo "🧪 Running tests..."
	$(SWIFT) test $(SWIFTFLAGS)

# Run tests with coverage
test-coverage:
	@echo "🧪 Running tests with coverage..."
	$(SWIFT) test $(SWIFTFLAGS) --enable-code-coverage
	@echo "📊 Generating coverage report..."
	xcrun llvm-cov export -format="lcov" $(BUILD_DIR)/MacOSFixerTests.xctest/Contents/MacOS/MacOSFixerTests -instr-profile=$(BUILD_DIR)/codecov/default.profdata > coverage.lcov

# Run the application
run: build
	@echo "🚀 Running $(TARGET)..."
	$(BINARY) --help

# Run diagnostics
diagnose: build
	$(BINARY) diagnose --detailed

# Run repair (dry-run)
repair-dry: build
	$(BINARY) repair --dry-run

# Run cleanup (dry-run)
cleanup-dry: build
	$(BINARY) cleanup --dry-run

# Run performance analysis
performance: build
	$(BINARY) performance --duration 30

# Show machine overview
overview: build
	$(BINARY) overview

# Start web dashboard
dashboard: build
	$(BINARY) dashboard --port 8080 --open

# Install to /usr/local/bin
install: build
	@echo "📦 Installing to /usr/local/bin..."
	sudo cp $(BINARY) /usr/local/bin/$(TARGET)
	@echo "✅ Installed! Run '$(TARGET) --help'"

# Uninstall
uninstall:
	@echo "🗑️ Uninstalling..."
	sudo rm -f /usr/local/bin/$(TARGET)
	@echo "✅ Uninstalled"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning..."
	$(SWIFT) package clean
	rm -rf .build
	@echo "✅ Clean complete"

# Format code
format:
	@echo "🎨 Formatting code..."
	swift-format --in-place --recursive Sources Tests

# Lint code
lint:
	@echo "🔍 Linting..."
	swiftlint lint --path Sources --path Tests

# Create release build
release: clean
	@echo "📦 Creating release build..."
	$(SWIFT) build -c release --disable-sandbox --static-swift-stdlib
	@echo "✅ Release binary: $(BINARY)"

# Build universal binary (Intel + Apple Silicon)
universal: clean
	@echo "🔨 Building universal binary..."
	$(SWIFT) build -c release --disable-sandbox --arch arm64 --arch x86_64
	@echo "✅ Universal binary: $(BINARY)"

# Package as .app bundle (real Info.plist lives in Resources/Info.plist)
app-bundle: release
	@echo "📦 Creating .app bundle..."
	@rm -rf MacOSFixer.app
	@mkdir -p MacOSFixer.app/Contents/MacOS
	@cp $(BINARY) MacOSFixer.app/Contents/MacOS/$(TARGET)
	@chmod +x MacOSFixer.app/Contents/MacOS/$(TARGET)
	@cp Resources/Info.plist MacOSFixer.app/Contents/Info.plist
	@codesign -f -s - MacOSFixer.app
	@echo "✅ App bundle created & ad-hoc signed: MacOSFixer.app"

# Create DMG installer
dmg: app-bundle
	@echo "💿 Creating DMG..."
	@rm -rf dmg-staging $(DMG_NAME)
	@mkdir dmg-staging
	@cp -R MacOSFixer.app dmg-staging/
	@ln -s /Applications dmg-staging/Applications
	@cp README.md LICENSE dmg-staging/
	hdiutil create -volname "MacOSFixer" -srcfolder dmg-staging -ov -format UDZO -imagekey zlib-level=9 $(DMG_NAME)
	@rm -rf dmg-staging
	@echo "✅ DMG created: $(DMG_NAME)"

# Bump version: `make bump-version VERSION=patch|minor|major` or `make bump-version VERSION=1.2.3`
# Pass the new version via the VERSION variable (avoids phony-target conflicts).
bump-version:
	@python3 Version.py $(VERSION)

# Sign the app bundle with a Developer ID (or ad-hoc with no SIGN_ID)
sign: app-bundle
	@echo "✍️ Signing MacOSFixer.app with '$(SIGN_ID)'..."
	codesign --force --deep --sign "$(SIGN_ID)" \
		--options runtime \
		--timestamp \
		MacOSFixer.app
	@codesign --verify --deep --strict --verbose=2 MacOSFixer.app
	@echo "✅ Signed & verified"

# Notarize the DMG and staple the ticket (requires Apple Developer account)
notarize: dmg
	@echo "📤 Submitting $(DMG_NAME) for notarization..."
	xcrun notarytool submit $(DMG_NAME) \
		--apple-id "$(NOTARY_EMAIL)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait
	@echo "📌 Stapling notarization ticket..."
	xcrun stapler staple MacOSFixer.app
	@echo "✅ Notarized & stapled"

# Full release pipeline: build -> sign -> notarize -> DMG
dmg-release: sign notarize
	@echo "🎉 Release complete: $(DMG_NAME)"

# Generate Xcode project
xcode:
	@echo "📝 Generating Xcode project..."
	$(SWIFT) package generate-xcodeproj

# Update dependencies
update:
	@echo "📦 Updating dependencies..."
	$(SWIFT) package update

# Resolve dependencies
resolve:
	@echo "📦 Resolving dependencies..."
	$(SWIFT) package resolve

# Show help
help:
	@echo "MacOSFixer Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build          Build release version"
	@echo "  build-debug    Build debug version"
	@echo "  test           Run tests"
	@echo "  test-coverage  Run tests with coverage"
	@echo "  run            Run the application"
	@echo "  diagnose       Run system diagnostics"
	@echo "  repair-dry     Run repair in dry-run mode"
	@echo "  cleanup-dry    Run cleanup in dry-run mode"
	@echo "  performance    Run performance analysis"
	@echo "  overview       Show machine overview"
	@echo "  dashboard      Start web dashboard"
	@echo "  install        Install to /usr/local/bin"
	@echo "  uninstall      Uninstall from /usr/local/bin"
	@echo "  clean          Clean build artifacts"
	@echo "  format         Format code with swift-format"
	@echo "  lint           Lint code with swiftlint"
	@echo "  release        Create release build"
	@echo "  universal      Create universal binary"
	@echo "  app-bundle     Create .app bundle"
	@echo "  dmg            Create DMG installer"
		echo "  bump-version   Bump version (patch|minor|major or x.y.z)"
		echo "  sign           Sign app bundle with Developer ID"
		echo "  notarize       Notarize DMG and staple ticket"
		echo "  dmg-release    Full pipeline: sign + notarize"
	@echo "  xcode          Generate Xcode project"
	@echo "  update         Update dependencies"
	@echo "  resolve        Resolve dependencies"
	@echo "  help           Show this help"
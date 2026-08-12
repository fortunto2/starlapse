.PHONY: help gen build build-device test integration lint fmt install archive open device clean

SCHEME  := Starlapse
PROJECT := Starlapse.xcodeproj
DEVICE  := Rust's iPhone
# Alanya, Turkey — change for your own sky, or pass LAT=… LON=…
LAT     ?= 36.545
LON     ?= 32.0

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

gen: ## Regenerate the Xcode project from project.yml
	@xcodegen generate

test: ## Run the domain tests (no simulator, ~3s)
	@swift test

integration: ## Run the CLI against the real sky — deterministic, no UI
	@swift run -q starlapse-sky tonight --lat $(LAT) --lon $(LON)
	@swift run -q starlapse-sky moon --lat $(LAT) --lon $(LON)

build: gen ## Build for the simulator (fast compile check)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO build 2>&1 | \
		grep -E "(error:|warning:|BUILD)" | head -30

build-device: gen ## Build for a physical iPhone (needs an Apple ID in Xcode)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-sdk iphoneos -destination 'generic/platform=iOS' \
		-derivedDataPath build -allowProvisioningUpdates build 2>&1 | \
		grep -E "(error:|BUILD)" | head -30

install: build-device ## Build and install onto the paired iPhone
	@xcrun devicectl device install app \
		--device "$(DEVICE)" \
		build/Build/Products/Debug-iphoneos/Starlapse.app

archive: gen ## Archive for distribution
	@xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-archivePath build/$(SCHEME).xcarchive -allowProvisioningUpdates

open: ## Open the archive for Distribute App
	@open build/$(SCHEME).xcarchive

device: ## List paired physical devices
	@xcrun devicectl list devices

lint: ## Run SwiftLint
	@swiftlint lint --quiet

fmt: ## Autocorrect what SwiftLint can fix
	@swiftlint --fix --quiet

clean: ## Remove build artifacts and the generated project
	@rm -rf build build-sim build-test .build $(PROJECT)

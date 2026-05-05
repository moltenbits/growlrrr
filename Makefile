.PHONY: build release clean test install uninstall bundle notarize notarize-submit notarize-finalize notarize-status

# Build configuration
SWIFT_BUILD_FLAGS = --disable-sandbox
RELEASE_FLAGS = -c release $(SWIFT_BUILD_FLAGS)
DEBUG_FLAGS = -c debug $(SWIFT_BUILD_FLAGS)
APP_INSTALL_PATH = /Applications
BIN_INSTALL_PATH = /usr/local/bin

help: ## This help screen
	@IFS=$$'\n' ; \
	help_lines=(`fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##/:/'`); \
	printf "%-30s %s\n" "Target" "Function" ; \
	printf "%-30s %s\n" "------" "----" ; \
	for help_line in $${help_lines[@]}; do \
		IFS=$$':' ; \
		help_split=($$help_line) ; \
		help_command=`echo $${help_split[0]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
		help_info=`echo $${help_split[2]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
		printf '\033[36m'; \
		printf "%-30s %s" $$help_command ; \
		printf '\033[0m'; \
		printf "%s\n" $$help_info; \
	done

all: ## Default target
all: bundle

build: ## Build debug executable only (no app bundle)
	swift build $(DEBUG_FLAGS)

release: ## Build release executable only (no app bundle)
	swift build $(RELEASE_FLAGS)

bundle: ## Build debug app bundle
	./scripts/bundle.sh debug

bundle-release: ## Build release app bundle
	./scripts/bundle.sh release

test: ## Run tests
	swift test $(SWIFT_BUILD_FLAGS)

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build

install: ## Install app bundle and CLI symlink (may require sudo)
install: bundle-release
	@echo "Installing growlrrr.app to $(APP_INSTALL_PATH)..."
	@if [ -w $(APP_INSTALL_PATH) ]; then \
		cp -r .build/release/growlrrr.app $(APP_INSTALL_PATH)/; \
	else \
		sudo cp -r .build/release/growlrrr.app $(APP_INSTALL_PATH)/; \
	fi
	@echo "Creating symlinks at $(BIN_INSTALL_PATH)..."
	@if [ -w $(BIN_INSTALL_PATH) ]; then \
		ln -sf $(APP_INSTALL_PATH)/growlrrr.app/Contents/MacOS/growlrrr $(BIN_INSTALL_PATH)/growlrrr; \
		ln -sf $(BIN_INSTALL_PATH)/growlrrr $(BIN_INSTALL_PATH)/grrr; \
	else \
		sudo ln -sf $(APP_INSTALL_PATH)/growlrrr.app/Contents/MacOS/growlrrr $(BIN_INSTALL_PATH)/growlrrr; \
		sudo ln -sf $(BIN_INSTALL_PATH)/growlrrr $(BIN_INSTALL_PATH)/grrr; \
	fi
	killall NotificationCenter
	@echo "Installed! Run 'hash -r' to refresh your shell, then 'growlrrr --help' to get started."
	@echo "Tip: 'grrr' is available as a shortcut for 'growlrrr'"

uninstall: ## Uninstall (may require sudo)
	@rm -f $(BIN_INSTALL_PATH)/growlrrr $(BIN_INSTALL_PATH)/grrr 2>/dev/null || \
		sudo rm -f $(BIN_INSTALL_PATH)/growlrrr $(BIN_INSTALL_PATH)/grrr
	@rm -rf $(APP_INSTALL_PATH)/growlrrr.app 2>/dev/null || \
		sudo rm -rf $(APP_INSTALL_PATH)/growlrrr.app
	@echo "Uninstalled growlrrr"

run: ## Run the debug build (via app bundle)
run: bundle
	.build/debug/growlrrr.app/Contents/MacOS/growlrrr "Test notification from growlrrr"

xcode: ## Generate Xcode project (for development)
	swift package generate-xcodeproj

format: ## Format code (requires swift-format)
	swift-format -i -r Sources/

lint: ## Lint code (requires swift-format)
	swift-format lint -r Sources/

notarize: ## Build, notarize (waits up to NOTARY_TIMEOUT, default 30m), and staple
notarize: notarize-submit notarize-finalize

notarize-submit: ## Build, sign, and submit to Apple notary (returns immediately, ID saved)
notarize-submit: bundle-release
	@set -e; \
	APP_BUNDLE=.build/release/growlrrr.app; \
	ZIP_PATH=.build/release/growlrrr.zip; \
	ID_FILE=.build/release/notary-id; \
	echo "Verifying signature on $$APP_BUNDLE..."; \
	codesign --verify --deep --strict --verbose=2 "$$APP_BUNDLE"; \
	echo "Zipping for notarization..."; \
	rm -f "$$ZIP_PATH"; \
	ditto -c -k --keepParent "$$APP_BUNDLE" "$$ZIP_PATH"; \
	if [ -n "$$APPLE_ID" ] && [ -n "$$APPLE_ID_PASSWORD" ] && [ -n "$$TEAM_ID" ]; then \
		echo "Submitting to Apple notary service (inline credentials)..."; \
		SUBMIT_ID=$$(xcrun notarytool submit "$$ZIP_PATH" \
			--apple-id "$$APPLE_ID" \
			--password "$$APPLE_ID_PASSWORD" \
			--team-id "$$TEAM_ID" \
			--output-format json | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4); \
	else \
		PROFILE=$${NOTARY_PROFILE:-growlrrr-notarization}; \
		echo "Submitting to Apple notary service (keychain profile: $$PROFILE)..."; \
		SUBMIT_ID=$$(xcrun notarytool submit "$$ZIP_PATH" \
			--keychain-profile "$$PROFILE" \
			--output-format json | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4); \
	fi; \
	if [ -z "$$SUBMIT_ID" ]; then echo "Failed to extract submission ID"; exit 1; fi; \
	echo "$$SUBMIT_ID" > "$$ID_FILE"; \
	echo "Submitted: $$SUBMIT_ID"; \
	echo "Saved to:  $$ID_FILE"; \
	echo ""; \
	echo "Run 'make notarize-status' to check, or 'make notarize-finalize' to wait + staple."

notarize-status: ## Check the status of the most recent submission
	@set -e; \
	ID_FILE=.build/release/notary-id; \
	if [ ! -f "$$ID_FILE" ]; then echo "No submission ID file at $$ID_FILE"; exit 1; fi; \
	SUBMIT_ID=$$(cat "$$ID_FILE"); \
	echo "Checking status of $$SUBMIT_ID..."; \
	if [ -n "$$APPLE_ID" ] && [ -n "$$APPLE_ID_PASSWORD" ] && [ -n "$$TEAM_ID" ]; then \
		xcrun notarytool info "$$SUBMIT_ID" \
			--apple-id "$$APPLE_ID" --password "$$APPLE_ID_PASSWORD" --team-id "$$TEAM_ID"; \
	else \
		PROFILE=$${NOTARY_PROFILE:-growlrrr-notarization}; \
		xcrun notarytool info "$$SUBMIT_ID" --keychain-profile "$$PROFILE"; \
	fi

notarize-finalize: ## Wait for the most recent submission, then staple + re-zip
	@set -e; \
	APP_BUNDLE=.build/release/growlrrr.app; \
	ZIP_PATH=.build/release/growlrrr.zip; \
	ID_FILE=.build/release/notary-id; \
	if [ ! -f "$$ID_FILE" ]; then echo "No submission ID file at $$ID_FILE"; exit 1; fi; \
	SUBMIT_ID=$$(cat "$$ID_FILE"); \
	NOTARY_TIMEOUT=$${NOTARY_TIMEOUT:-30m}; \
	echo "Waiting on $$SUBMIT_ID (timeout $$NOTARY_TIMEOUT)..."; \
	if [ -n "$$APPLE_ID" ] && [ -n "$$APPLE_ID_PASSWORD" ] && [ -n "$$TEAM_ID" ]; then \
		xcrun notarytool wait "$$SUBMIT_ID" \
			--apple-id "$$APPLE_ID" --password "$$APPLE_ID_PASSWORD" --team-id "$$TEAM_ID" \
			--timeout "$$NOTARY_TIMEOUT"; \
	else \
		PROFILE=$${NOTARY_PROFILE:-growlrrr-notarization}; \
		xcrun notarytool wait "$$SUBMIT_ID" \
			--keychain-profile "$$PROFILE" --timeout "$$NOTARY_TIMEOUT"; \
	fi; \
	echo "Stapling notarization ticket..."; \
	xcrun stapler staple "$$APP_BUNDLE"; \
	xcrun stapler validate "$$APP_BUNDLE"; \
	echo "Re-zipping notarized bundle..."; \
	rm -f "$$ZIP_PATH"; \
	ditto -c -k --keepParent "$$APP_BUNDLE" "$$ZIP_PATH"; \
	rm -f "$$ID_FILE"; \
	echo "Done. Notarized bundle: $$APP_BUNDLE"; \
	echo "Distributable zip:    $$ZIP_PATH"

flush-icon-cache: ## Flush macOS icon caches and restart related services
	@echo "Flushing icon caches..."
	@find /var/folders -maxdepth 5 -name "com.apple.iconservicesagent" -path "*/C/*" -exec rm -rf {} + 2>/dev/null || true
	@find /var/folders -maxdepth 5 -name "com.apple.iconservices" -path "*/C/*" -exec rm -rf {} + 2>/dev/null || true
	@find /var/folders -maxdepth 5 -name "com.apple.dock.iconcache" -exec rm -rf {} + 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@killall usernoted 2>/dev/null || true
	@killall NotificationCenter 2>/dev/null || true
	@echo "Done. Icon caches flushed and services restarted."

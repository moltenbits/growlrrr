.PHONY: build release clean test install uninstall bundle

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

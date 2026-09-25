APP_NAME := SchreibtischUnterlage
BUILD_APP := .build/$(APP_NAME).app
INSTALL_DIRECTORY ?= /Applications
INSTALL_APP := $(INSTALL_DIRECTORY)/$(APP_NAME).app
INSTALL_EXECUTABLE := $(INSTALL_APP)/Contents/MacOS/$(APP_NAME)
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build test app install reinstall clean

build:
	swift build --arch arm64 --product SchreibtischUnterlage

test:
	swift test --arch arm64

app:
	./Scripts/build-app.sh

install: app
	@if ps -axo comm= | grep -Fqx "$(INSTALL_EXECUTABLE)"; then \
		echo "Quit SU before installing a new build."; \
		exit 1; \
	fi
	rm -rf "$(INSTALL_APP)"
	/usr/bin/ditto "$(BUILD_APP)" "$(INSTALL_APP)"
	"$(LSREGISTER)" -f "$(INSTALL_APP)"
	/usr/bin/codesign --verify --deep --strict "$(INSTALL_APP)"
	@echo "Installed SU at $(INSTALL_APP)"

reinstall: install
	/usr/bin/open "$(INSTALL_APP)"

clean:
	swift package clean

# LaneKeep — build and install from the command line.
#
#   make build             Build LaneKeep.app (Release) into build/
#   make run               Build and open it
#   make install           Copy it to /Applications and open it
#   make test              Run the unit tests of LaneKeepKit
#   make cli               Build the lanekeep command-line tool
#   make reset-permission  Forget the accessibility permission (e.g. after re-signing)
#   make clean             Remove build products

PROJECT       := LaneKeep.xcodeproj
SCHEME        := LaneKeep
CONFIGURATION ?= Release
BUILD_DIR     := build
APP           := $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/LaneKeep.app
PACKAGE       := Packages/LaneKeepKit
BUNDLE_ID     := io.github.enomoso-pm.LaneKeep

.PHONY: build run install test cli reset-permission clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination 'generic/platform=macOS' -derivedDataPath $(BUILD_DIR) build

run: build
	open "$(APP)"

install: build
	-pkill -x LaneKeep
	rm -rf /Applications/LaneKeep.app
	cp -R "$(APP)" /Applications/
	open /Applications/LaneKeep.app

test:
	swift test --package-path $(PACKAGE)

cli:
	swift build --package-path $(PACKAGE) --configuration release --product lanekeep
	@echo "Built $(PACKAGE)/.build/release/lanekeep"

reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf $(BUILD_DIR)
	swift package --package-path $(PACKAGE) clean

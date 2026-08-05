APP      := build/OutcutShare.app
BINARY   := .build/release/OutcutShare
ASSETS   := Resources/Assets.xcassets
ASSET_FILES := $(shell find $(ASSETS) -type f)
ASSET_INFO := build/AppIconInfo.plist
LOCALIZATION_CATALOGS := Resources/Localization/Localizable.xcstrings \
	Resources/Localization/InfoPlist.xcstrings

VERSION  ?= 1.17.0
BUILD    := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
HASH     := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

# A stable signing identity keeps the Screen Recording grant across rebuilds;
# ad-hoc signatures change every build and make macOS re-ask each time.
# Override with `make app CODESIGN_ID=<sha1-or-name>` if needed.
CODESIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -m1 "Apple Development" | awk '{print $$2}')
ifeq ($(strip $(CODESIGN_ID)),)
CODESIGN_ID := -
endif

.PHONY: app test run clean release

app: $(APP)

$(APP): Support/Info.plist $(ASSET_FILES) $(LOCALIZATION_CATALOGS) \
		$(shell find Sources -type f) Package.swift Makefile Scripts/verify-localizations.sh
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/OutcutShare
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp Resources/DemoBackdrop.jpg $(APP)/Contents/Resources/
	xcrun xcstringstool compile Resources/Localization/Localizable.xcstrings \
		--output-directory $(APP)/Contents/Resources
	xcrun xcstringstool compile Resources/Localization/InfoPlist.xcstrings \
		--output-directory $(APP)/Contents/Resources
	xcrun actool \
		--compile $(APP)/Contents/Resources \
		--platform macosx \
		--minimum-deployment-target 14.0 \
		--app-icon AppIcon \
		--standalone-icon-behavior all \
		--output-partial-info-plist $(ASSET_INFO) \
		--output-format human-readable-text \
		--warnings \
		--notices \
		$(ASSETS)
	/usr/libexec/PlistBuddy \
		-c "Merge $(ASSET_INFO)" \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(BUILD).$(HASH)" \
		$(APP)/Contents/Info.plist
	Scripts/verify-localizations.sh $(APP)
	codesign --force -s "$(CODESIGN_ID)" $(APP)
	@echo "Built $(APP) v$(VERSION) ($(BUILD).$(HASH), signed as $(CODESIGN_ID))"

test:
	swift test

run: app
	open $(APP)

clean:
	rm -rf build .build

release:
	Scripts/release.sh

APP      := build/RegionShare.app
BINARY   := .build/release/RegionShare

VERSION  ?= 1.1
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

.PHONY: app test run clean

app: $(APP)

$(APP): Support/Info.plist $(shell find Sources -type f) Package.swift
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/RegionShare
	cp Support/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(BUILD).$(HASH)" \
		$(APP)/Contents/Info.plist
	codesign --force -s "$(CODESIGN_ID)" $(APP)
	@echo "Built $(APP) v$(VERSION) ($(BUILD).$(HASH), signed as $(CODESIGN_ID))"

test:
	swift test

run: app
	open $(APP)

clean:
	rm -rf build .build

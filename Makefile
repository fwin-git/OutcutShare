APP      := build/RegionShare.app
BINARY   := .build/release/RegionShare

.PHONY: app test run clean

app: $(APP)

$(APP): Support/Info.plist $(shell find Sources -type f) Package.swift
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/RegionShare
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force -s - $(APP)
	@echo "Built $(APP)"

test:
	swift test

run: app
	open $(APP)

clean:
	rm -rf build .build

.PHONY: build test app dmg run clean

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

build:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build --disable-sandbox

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift test --disable-sandbox

app:
	DEVELOPER_DIR=$(DEVELOPER_DIR) ./scripts/build-app.sh

dmg:
	DEVELOPER_DIR=$(DEVELOPER_DIR) ./scripts/build-dmg.sh

run: app
	open "dist/Password Bridge.app"

clean:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift package clean
	rm -rf dist

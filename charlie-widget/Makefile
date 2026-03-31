.PHONY: build release install uninstall run-app test-toast test clean icon

APP_NAME = CharlieWidget
APP_BUNDLE = $(APP_NAME).app
APP_INSTALL_DIR = /Applications
LAUNCHAGENT_PLIST = ~/Library/LaunchAgents/com.charlie.widget.plist

build:
	swift build

release:
	swift build -c release

icon:
	swift generate-icon.swift

install: release icon
	@# CLI
	cp .build/release/charlie-widget ~/.local/bin/
	@# App bundle
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Resources
	cp .build/release/CharlieWidgetApp $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/CharlieWidgetApp
	cp /tmp/AppIcon.icns $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cat > $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Info.plist << 'PLIST'
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	    <key>CFBundleExecutable</key>
	    <string>CharlieWidgetApp</string>
	    <key>CFBundleIdentifier</key>
	    <string>com.charlie.widget</string>
	    <key>CFBundleName</key>
	    <string>CharlieWidget</string>
	    <key>CFBundleIconFile</key>
	    <string>AppIcon</string>
	    <key>LSUIElement</key>
	    <true/>
	</dict>
	</plist>
	PLIST
	@echo "Installed to $(APP_INSTALL_DIR)/$(APP_BUNDLE)"
	@# LaunchAgent for login startup
	@cat > $(LAUNCHAGENT_PLIST) << 'PLIST'
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	    <key>Label</key>
	    <string>com.charlie.widget</string>
	    <key>ProgramArguments</key>
	    <array>
	        <string>$(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/CharlieWidgetApp</string>
	    </array>
	    <key>RunAtLoad</key>
	    <true/>
	    <key>KeepAlive</key>
	    <false/>
	</dict>
	</plist>
	PLIST
	launchctl load $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	@echo "LaunchAgent installed — will start on login"

uninstall:
	launchctl unload $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	rm -f $(LAUNCHAGENT_PLIST)
	rm -rf $(APP_INSTALL_DIR)/$(APP_BUNDLE)
	rm -f ~/.local/bin/charlie-widget
	rm -rf ~/Library/Application\ Support/CharlieWidget
	@echo "Uninstalled"

run-app:
	swift run CharlieWidgetApp

test-toast:
	swift run charlie-widget toast --title "Test" --subtitle "Hello" --body "This is a test toast notification"

test:
	swift test

clean:
	swift package clean

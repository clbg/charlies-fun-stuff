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
	@# Hook script
	cp scripts/cc-monitor-hook.sh ~/.local/bin/cc-monitor-hook.sh
	chmod +x ~/.local/bin/cc-monitor-hook.sh
	@# App bundle
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Resources
	cp .build/release/CharlieWidgetApp $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/CharlieWidgetApp
	cp /tmp/AppIcon.icns $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
	<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
	<plist version=\"1.0\">\n\
	<dict>\n\
	    <key>CFBundleExecutable</key>\n\
	    <string>CharlieWidgetApp</string>\n\
	    <key>CFBundleIdentifier</key>\n\
	    <string>com.charlie.widget</string>\n\
	    <key>CFBundleName</key>\n\
	    <string>CharlieWidget</string>\n\
	    <key>CFBundleIconFile</key>\n\
	    <string>AppIcon</string>\n\
	    <key>LSUIElement</key>\n\
	    <true/>\n\
	</dict>\n\
	</plist>\n" > $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Info.plist
	@echo "Installed to $(APP_INSTALL_DIR)/$(APP_BUNDLE)"
	@# LaunchAgent for login startup
	@printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
	<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
	<plist version=\"1.0\">\n\
	<dict>\n\
	    <key>Label</key>\n\
	    <string>com.charlie.widget</string>\n\
	    <key>ProgramArguments</key>\n\
	    <array>\n\
	        <string>$(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/CharlieWidgetApp</string>\n\
	    </array>\n\
	    <key>RunAtLoad</key>\n\
	    <true/>\n\
	    <key>KeepAlive</key>\n\
	    <false/>\n\
	</dict>\n\
	</plist>\n" > $(LAUNCHAGENT_PLIST)
	launchctl load $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	@echo "LaunchAgent installed — will start on login"

uninstall:
	launchctl unload $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	rm -f $(LAUNCHAGENT_PLIST)
	rm -rf $(APP_INSTALL_DIR)/$(APP_BUNDLE)
	rm -f ~/.local/bin/charlie-widget
	rm -f ~/.local/bin/cc-monitor-hook.sh
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

.PHONY: build release install uninstall run-app test-toast test clean

APP_NAME = CharlieWidget
APP_BUNDLE = $(APP_NAME).app
APP_INSTALL_DIR = /Applications
LAUNCHAGENT_PLIST = ~/Library/LaunchAgents/com.charlie.widget.plist

build:
	swift build

release:
	swift build -c release

install: release
	@# CLI
	cp .build/release/charlie-widget ~/.local/bin/
	@# App bundle
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS
	cp .build/release/CharlieWidgetApp $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/CharlieWidgetApp
	@echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
<key>CFBundleExecutable</key><string>CharlieWidgetApp</string>\n\
<key>CFBundleIdentifier</key><string>com.charlie.widget</string>\n\
<key>CFBundleName</key><string>CharlieWidget</string>\n\
<key>LSUIElement</key><true/>\n\
</dict></plist>' > $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Info.plist
	@echo "Installed to $(APP_INSTALL_DIR)/$(APP_BUNDLE)"
	@# LaunchAgent for login startup
	@echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
<key>Label</key><string>com.charlie.widget</string>\n\
<key>ProgramArguments</key><array><string>$(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/CharlieWidgetApp</string></array>\n\
<key>RunAtLoad</key><true/>\n\
<key>KeepAlive</key><false/>\n\
</dict></plist>' > $(LAUNCHAGENT_PLIST)
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

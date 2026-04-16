.PHONY: build release install uninstall run-app test-toast test test-recorder clean icon

APP_NAME = CharlieWidget
APP_BUNDLE = $(APP_NAME).app
APP_INSTALL_DIR = /Applications
LAUNCHAGENT_LABEL = com.charlie.widget
LAUNCHAGENT_PLIST = ~/Library/LaunchAgents/com.charlie.widget.plist
LAUNCHCTL_DOMAIN = gui/$(shell id -u)

build:
	swift build

release:
	swift build -c release

icon:
	swift generate-icon.swift

install: release icon
	@# Kill any debug instance first to avoid duplicates
	@pkill -f '.build/debug/CharlieWidgetApp' 2>/dev/null || true
	@# CLI
	cp .build/release/charlie-widget ~/.local/bin/
	@# Hook scripts
	cp scripts/cc-monitor-hook.sh ~/.local/bin/cc-monitor-hook.sh
	cp scripts/codex-monitor-hook.sh ~/.local/bin/codex-monitor-hook.sh
	cp scripts/gemini-monitor-hook.sh ~/.local/bin/gemini-monitor-hook.sh
	chmod +x ~/.local/bin/cc-monitor-hook.sh
	chmod +x ~/.local/bin/codex-monitor-hook.sh
	chmod +x ~/.local/bin/gemini-monitor-hook.sh
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
	launchctl bootout $(LAUNCHCTL_DOMAIN) $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	launchctl bootstrap $(LAUNCHCTL_DOMAIN) $(LAUNCHAGENT_PLIST)
	launchctl kickstart -k $(LAUNCHCTL_DOMAIN)/$(LAUNCHAGENT_LABEL)
	@echo "LaunchAgent installed and CharlieWidget restarted"

uninstall:
	launchctl unload $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	rm -f $(LAUNCHAGENT_PLIST)
	rm -rf $(APP_INSTALL_DIR)/$(APP_BUNDLE)
	rm -f ~/.local/bin/charlie-widget
	rm -f ~/.local/bin/cc-monitor-hook.sh
	rm -f ~/.local/bin/codex-monitor-hook.sh
	rm -f ~/.local/bin/gemini-monitor-hook.sh
	rm -rf ~/Library/Application\ Support/CharlieWidget
	@echo "Uninstalled"

run-app:
	swift run CharlieWidgetApp

test-toast:
	swift run charlie-widget toast --title "Test" --subtitle "Hello" --body "This is a test toast notification"

test:
	swift test

test-recorder:
	bash scripts/test-recorder.sh

clean:
	swift package clean

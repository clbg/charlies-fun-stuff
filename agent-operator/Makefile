.PHONY: build release install uninstall run-app test-hello test clean sip-up sip-down sip-config sip-reload

APP_NAME = AgentOperator
APP_BUNDLE = $(APP_NAME).app
APP_INSTALL_DIR = /Applications
LAUNCHAGENT_LABEL = com.charlie.agentoperator
LAUNCHAGENT_PLIST = ~/Library/LaunchAgents/com.charlie.agentoperator.plist
LAUNCHCTL_DOMAIN = gui/$(shell id -u)

build:
	swift build

release:
	swift build -c release

install: release
	@# Kill ALL running instances first to avoid duplicates
	@pkill -f AgentOperatorApp 2>/dev/null || true
	@sleep 1
	@# CLI
	cp .build/release/agent-operator ~/.local/bin/
	@# App bundle
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Resources
	cp .build/release/AgentOperatorApp $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/AgentOperatorApp
	@printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
	<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
	<plist version=\"1.0\">\n\
	<dict>\n\
	    <key>CFBundleExecutable</key>\n\
	    <string>AgentOperatorApp</string>\n\
	    <key>CFBundleIdentifier</key>\n\
	    <string>com.charlie.agentoperator</string>\n\
	    <key>CFBundleName</key>\n\
	    <string>AgentOperator</string>\n\
	    <key>LSUIElement</key>\n\
	    <true/>\n\
	</dict>\n\
	</plist>\n" > $(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/Info.plist
	@# Code sign with stable identity so TCC permissions persist across rebuilds
	@codesign --force --sign "AgentOperator Dev" $(APP_INSTALL_DIR)/$(APP_BUNDLE) 2>/dev/null \
		&& echo "Signed with AgentOperator Dev certificate" \
		|| echo "Warning: No signing identity found, using ad-hoc"
	@echo "Installed to $(APP_INSTALL_DIR)/$(APP_BUNDLE)"
	@# LaunchAgent for login startup
	@printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
	<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
	<plist version=\"1.0\">\n\
	<dict>\n\
	    <key>Label</key>\n\
	    <string>com.charlie.agentoperator</string>\n\
	    <key>ProgramArguments</key>\n\
	    <array>\n\
	        <string>$(APP_INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/AgentOperatorApp</string>\n\
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
	@echo "LaunchAgent installed and AgentOperator restarted"

uninstall:
	launchctl unload $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	rm -f $(LAUNCHAGENT_PLIST)
	rm -rf $(APP_INSTALL_DIR)/$(APP_BUNDLE)
	rm -f ~/.local/bin/agent-operator
	rm -rf ~/Library/Application\ Support/AgentOperator
	@echo "Uninstalled"

run-app:
	swift run AgentOperatorApp

test-hello:
	swift run agent-operator hello

test:
	swift test

clean:
	swift package clean

# ── Asterisk / SIP targets ──────────────────────────────────

ASTERISK_CONF_DIR = /opt/homebrew/etc/asterisk

sip-up: sip-config
	brew services start asterisk

sip-down:
	brew services stop asterisk

sip-config:
	cp asterisk/pjsip.conf $(ASTERISK_CONF_DIR)/pjsip.conf
	cp asterisk/extensions.conf $(ASTERISK_CONF_DIR)/extensions.conf
	cp asterisk/ari.conf $(ASTERISK_CONF_DIR)/ari.conf
	cp asterisk/http.conf $(ASTERISK_CONF_DIR)/http.conf
	cp asterisk/modules.conf $(ASTERISK_CONF_DIR)/modules.conf

sip-reload:
	asterisk -rx "core reload"

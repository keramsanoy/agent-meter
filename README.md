# Agent Meter

Agent Meter is a native macOS menu bar app that shows usage meters for Claude, GitHub Copilot, and ChatGPT Codex Cloud.

It uses app-owned WebKit browser sessions to load each provider's usage page in the background and read the visible usage values. Passwords are not stored by the app; sign-in state is handled by WebKit session cookies like a normal browser.

## Features

- Native macOS menu bar app built with SwiftUI and `MenuBarExtra`
- Provider toggles for Claude, GitHub Copilot, and Codex Cloud
- Text percentage display or a compact low-space color bar
- Automatic refresh every 10 minutes
- Dockless app mode
- Settings window for provider and display preferences

## Build

```sh
swift test
Scripts/install-app.sh
```

The install script builds the app and copies it to `/Applications/Agent Meter.app`.

## Release Bundle

A zipped app bundle can be created with:

```sh
ditto -c -k --sequesterRsrc --keepParent "/Applications/Agent Meter.app" "Agent-Meter-0.1.0-macOS.zip"
shasum -a 256 "Agent-Meter-0.1.0-macOS.zip" > "Agent-Meter-0.1.0-macOS.zip.sha256"
```

## Notes

This project depends on provider web pages staying parseable. If any provider changes its usage page, parsing may need to be updated.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project from project.yml (requires XcodeGen)
xcodegen generate

# Build
xcodebuild -scheme DenonController -configuration Debug -destination 'platform=macOS' build

# Release build
xcodebuild -scheme DenonController -configuration Release -destination 'platform=macOS' build
```

No test targets exist. Validation is manual against a physical Denon AVR-X3800H.

## Architecture

macOS menu bar + windowed app for controlling Denon/Marantz AV receivers over LAN. Pure Swift/SwiftUI, no external dependencies.

**Stack:** Swift 6.0, macOS 14.0+, SwiftUI with `@Observable`, strict concurrency (targeted)

### Data Flow

```
Views (@Environment) → MainViewModel (@Observable, @MainActor)
                         ├─ AVRHTTPClient (BSD sockets, port 8080)
                         │    ├─ Polling: XML status every 1.5s via AsyncStream
                         │    └─ Commands: /goform/formiPhoneAppDirect.xml?CMD
                         ├─ AVRState (observable state container)
                         ├─ PresetStore (UserDefaults persistence)
                         └─ InputNameStore (custom input naming)
```

### Key Design Decisions

- **BSD sockets over URLSession/NWConnection**: Apple's network stack performs internet reachability checks that fail on local-only WiFi. Raw sockets with `IP_BOUND_IF` interface binding bypass this.
- **`AppDelegate.shared` over `NSApp.delegate as? AppDelegate`**: The SwiftUI `@NSApplicationDelegateAdaptor` wraps the delegate such that the cast can silently return nil. A `nonisolated(unsafe) static weak var shared` set in `init()` is the reliable access pattern.
- **Window suppression via `alpha=0`**: In menuBarOnly mode, the WindowGroup window is hidden with `alphaValue=0` + `ignoresMouseEvents=true` instead of `orderOut`/`close`, which conflicts with SwiftUI's scene management. Restored via "Open Details" button.
- **Activation policy switching**: `.accessory` on launch (no Dock icon), `.regular` when showing window, `.accessory` again on window close.

### App Scenes (DenonControllerApp.swift)

| Scene | ID | Content |
|---|---|---|
| WindowGroup | `"main"` | ContentView — NavigationSplitView with sidebar |
| MenuBarExtra | — | MenuBarPopoverView — quick controls popover |
| Settings | — | SettingsView — connection, input naming, language |

### Networking Protocol (Denon AVR)

Commands are plain strings sent via HTTP GET to port 8080:
- Power: `PWON` / `PWSTANDBY`
- Volume: `MV##` (0–98), `MVUP`, `MVDOWN`
- Input: `SI<SOURCE>` (e.g. `SIHDMI1`, `SICD`)
- Surround: `MS<MODE>` (e.g. `MSMOVIE`, `MSMUSIC`)
- Zone 2/3: `Z2`/`Z3` prefix variants

Status polling parses XML from `/goform/formMainZone_MainZoneXmlStatusLite.xml`.

## Localization

- Development language: **Japanese** (set in `project.yml options.developmentLanguage: ja`)
- UI strings are Japanese literals in code; `en.lproj/Localizable.strings` provides English translations
- `ja.lproj/Localizable.strings` is an empty stub (signals Japanese locale support to the bundle system)
- Manual language override via `@AppStorage("appLanguage")` + `.environment(\.locale)`

## Entitlements

App Sandbox is **disabled** (required for BSD socket access). Network client entitlement is enabled. Bonjour service: `_denon-heos._tcp`.

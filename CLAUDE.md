# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project from project.yml (required after adding/removing files)
cd DenonController && xcodegen generate

# Build macOS app
xcodebuild -scheme DenonController -configuration Debug -destination 'platform=macOS' build

# Build iOS/iPadOS app (use an available simulator name from the list below)
xcodebuild -scheme DenonControllerMobile -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# List available iOS simulators (if the above fails)
xcodebuild -scheme DenonControllerMobile -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep "platform:iOS Simulator"
```

No test targets exist. Validation is manual against a physical Denon AVR-X3800H (or the simulator for UI-only changes).

**Important:** After creating or deleting `.swift` files in either target, always run `xcodegen generate` from the `DenonController/` directory before building.

## Repository Structure

```
symmetrical-carnival/
├── DenonController/               # Xcode project root
│   ├── project.yml                # XcodeGen spec (defines both targets)
│   ├── DenonController/           # macOS app sources
│   │   ├── App/                   # Entry point, AppDelegate
│   │   ├── Core/                  # Shared with iOS (see project.yml)
│   │   │   ├── Network/           # AVRHTTPClient, TelnetClient, MDNSDiscovery
│   │   │   ├── Models/            # AVRState, InputSource, SurroundMode, TunerPreset, …
│   │   │   └── Persistence/       # PresetStore, InputNameStore
│   │   ├── ViewModels/            # MainViewModel (shared with iOS)
│   │   └── Views/
│   │       ├── Shared/            # Shared with iOS: LocalizationHelper, VolumeControlView, CardView
│   │       └── MainWindow/        # macOS-only views
│   └── DenonControllerMobile/     # iOS/iPadOS app sources (separate directory)
│       ├── App/
│       └── Views/                 # iOS-specific views
└── DenonControllerMobile/         # iOS asset catalog and app entry point
    ├── App/
    ├── Assets.xcassets/
    └── Views/
```

## Shared Code Between Targets

Per `project.yml`, the iOS target (`DenonControllerMobile`) includes:
- `DenonController/Core/` — all models, networking, persistence
- `DenonController/ViewModels/` — MainViewModel
- `DenonController/Views/Shared/` — LocalizationHelper, VolumeControlView, CardView

macOS-only code (AppKit imports, NSApp, AppDelegate, window management) lives exclusively in `DenonController/Views/MainWindow/` and `DenonController/App/`.

## Architecture

Denon/Marantz AVR controller for macOS (menu bar + windowed) and iOS/iPadOS. Pure Swift/SwiftUI, no external dependencies.

**Stack:** Swift 6.0, macOS 14.0+ / iOS 26.0+, SwiftUI with `@Observable`, strict concurrency (targeted)

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
- **`AppDelegate.shared` over `NSApp.delegate as? AppDelegate`** (macOS): The SwiftUI `@NSApplicationDelegateAdaptor` wraps the delegate such that the cast can silently return nil. A `nonisolated(unsafe) static weak var shared` set in `init()` is the reliable access pattern.
- **Window suppression via `alpha=0`** (macOS): In menuBarOnly mode, the WindowGroup window is hidden with `alphaValue=0` + `ignoresMouseEvents=true` instead of `orderOut`/`close`, which conflicts with SwiftUI's scene management.
- **Surround mode spaces**: `SurroundMode.rawValue` contains spaces (e.g. `"PURE DIRECT"`) but the AVR command requires spaces removed. Use `.command` (not `.rawValue`) when sending. `rawValue` is preserved for Codable compatibility.

### Networking Protocol (Denon AVR)

Commands are plain strings sent via HTTP GET to port 8080:
- Power: `PWON` / `PWSTANDBY`
- Volume: `MV##` (0–98), `MVUP`, `MVDOWN`
- Input: `SI<SOURCE>` (e.g. `SIHDMI1`, `SICD`)
- Surround: `MS<MODE>` (spaces removed, e.g. `MSMOVIE`, `MSPUREDIRECT`)
- Zone 2/3: `Z2`/`Z3` prefix variants
- OSD Navigation: `MNCUP` / `MNCDN` / `MNCLT` / `MNCRT` (cursor), `MNENT` (enter), `MNRTN` (back), `MNINF` (info), `MNOPT` (option), `MNMEN` (setup menu)

Status polling parses XML from `/goform/formMainZone_MainZoneXmlStatusLite.xml`.
Tuner presets are fetched from `/goform/formTuner_TunerPresetXml.xml` (XML bulk fetch, falls back to Telnet scan).

## OSD Navigation (Remote Control) Implementation

**Target:** macOS only (`DenonController/Views/MainWindow/RemoteView.swift`)

**Files to change:**

| File | Change |
|------|--------|
| `DenonController/ViewModels/MainViewModel.swift` | Add `// MARK: - OSD Navigation` section with 9 methods after the Zone 3 block |
| `DenonController/Views/MainWindow/ContentView.swift` | Add `case remote = "リモコン"` to `NavSection`; add `.remote: RemoteView()` to detail switch |
| `DenonController/Views/MainWindow/RemoteView.swift` | New file — macOS-only remote control UI (direction pad + function buttons) |
| `DenonController/en.lproj/Localizable.strings` | Add English translations for all new UI strings |

**ViewModel methods to add** (`MainViewModel.swift`, after `zone3VolumeDown()`):
```swift
// MARK: - OSD Navigation
func cursorUp()     { send("MNCUP") }
func cursorDown()   { send("MNCDN") }
func cursorLeft()   { send("MNCLT") }
func cursorRight()  { send("MNCRT") }
func cursorEnter()  { send("MNENT") }
func back()         { send("MNRTN") }
func infoButton()   { send("MNINF") }
func optionButton() { send("MNOPT") }
func setupMenu()    { send("MNMEN") }
```

**UI layout** (`RemoteView.swift`):
```
┌─────────────────────────────┐
│  [情報]   [オプション] [設定] │  ← CardView: function buttons
│                             │
│          [ ↑ ]             │
│      [←] [決定] [→]        │  ← CardView: direction pad (3×3 grid)
│          [ ↓ ]             │
│                             │
│           [戻る]            │  ← CardView: back button
└─────────────────────────────┘
```

Reuse `CardView` (defined in `DashboardView.swift`, accessible within the same module).
`NavSection.remote` uses SF Symbol `tv.remote` (available on macOS 14+).

**Localization strings to add** (`en.lproj/Localizable.strings`):
```
"リモコン" = "Remote";
"情報" = "Info";
"オプション" = "Options";
"設定メニュー" = "Setup";
"決定" = "Enter";
"戻る" = "Back";
```

## Localization

- Development language: **Japanese** (keys are Japanese literals)
- `en.lproj/Localizable.strings` provides English translations; `ja.lproj/Localizable.strings` is an empty stub
- Manual language override via `@AppStorage("appLanguage")` → `"system"` / `"ja"` / `"en"`

**iOS-specific:** On iOS, `Text(LocalizedStringKey(...))` does NOT respect `\.locale` for string lookup — it uses `Bundle.main`'s system-language cache. The fix is to explicitly load the correct `.lproj` bundle and pass it to `Text("key", bundle: lBundle)`.

The helpers in `LocalizationHelper.swift` (shared):
- `localizedNavTitle(_ key:locale:) -> String` — for `.navigationTitle()` (both platforms)
- `makeLocalizedBundle(for:) -> Bundle` — returns the `.lproj` bundle for a given locale
- `LS(_ key:_ bundle:) -> String` — shorthand for `NSLocalizedString` with explicit bundle
- `\.localizedBundle` environment key — injected by `ContentView` (iOS), consumed by all mobile views

In iOS views, always add `@Environment(\.localizedBundle) private var lBundle` and use `Text("キー", bundle: lBundle)` / `LS("キー", lBundle)` for user-visible strings.

## SF Symbols

This project targets iOS 26+ and macOS 14+. When choosing SF Symbols, verify availability in SF Symbols app — some symbols (e.g. `satellite`) only exist in newer OS versions. Safe alternatives for input/media icons: `cable.connector`, `antenna.radiowaves.left.and.right.circle`, `opticaldisc`, `record.circle`.

## Entitlements

App Sandbox is **disabled** (required for BSD socket access). Network client entitlement is enabled. Bonjour service: `_denon-heos._tcp`.

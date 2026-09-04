# AVR Controller

AVR Controller is a native macOS, iOS, and iPadOS remote for network-enabled
Denon and Marantz AV receivers. It is designed for fast local-network control,
with a full app on every platform and quick access from the macOS menu bar.

The primary development and validation device is a Denon AVR-X3800H. Other
models that expose compatible Denon HTTP/Telnet commands may work, but behavior
can vary by model and firmware.

## Features

- Main Zone power, volume, mute, input, and surround-mode control
- Zone 2 and Zone 3 control when supported by the receiver
- FM/AM tuner control and preset scanning
- On-screen menu navigation (direction pad, Enter, Back, Info, Options, Setup)
- User presets for input, volume, and surround mode
- Bonjour/mDNS discovery and manual IP address entry
- Automatic rediscovery when a receiver's DHCP address changes
- macOS menu bar controls and a full control window
- iPhone tab-based UI and iPad split-view UI
- Japanese and English UI
- In-app help, privacy information, problem reporting, and review requests

## Architecture

The apps are written in Swift 6 using SwiftUI, Observation, and Swift
Concurrency. There are no third-party package dependencies.

```text
SwiftUI Views
    ↓
MainViewModel (@Observable, @MainActor)
    ├── AVRHTTPClient   HTTP commands and XML status polling
    ├── TelnetClient   real-time AVR notifications
    ├── MDNSDiscovery  Bonjour device discovery
    ├── AVRState       observable receiver state
    └── UserDefaults-backed preset and input-name stores
```

HTTP communication uses BSD sockets directly. This avoids internet-reachability
behavior that can interfere with local-only Wi-Fi and multi-interface setups.
The default HTTP API port is 8080; Telnet notifications use port 23.

See [docs/repository-overview.md](docs/repository-overview.md) for a detailed
snapshot of the repository and its current operational state.

## Requirements

- Xcode 16 or later
- XcodeGen
- macOS 14.0 or later for the Mac app
- iOS/iPadOS 17.0 or later for the mobile app
- A compatible Denon or Marantz AVR on the same local network

## Build

Generate the Xcode project after adding or removing Swift source files:

```bash
cd DenonController
xcodegen generate
cd ..
```

Build the macOS app:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project ./DenonController/DenonController.xcodeproj \
  -scheme DenonController \
  -destination 'platform=macOS,arch=arm64' build
```

Build the iOS app:

```bash
xcodebuild -project ./DenonController/DenonController.xcodeproj \
  -scheme DenonControllerMobile \
  -destination 'generic/platform=iOS' build
```

There are currently no automated test targets. UI-only changes can be checked
in a simulator; receiver integration requires a physical compatible AVR.

## Repository Layout

```text
DenonController/          XcodeGen project, macOS app, and shared Swift code
DenonControllerMobile/    iOS/iPadOS-specific app code and assets
help/                     Japanese and English GitHub Pages help site
server/                   Cloudflare Worker for GitHub problem reports
docs/                     Architecture, launch, and App Store documentation
```

The mobile target shares `Core`, `ViewModels`, `Views/Shared`, and localization
resources from the macOS source tree. `DenonController/project.yml` is the
source of truth for target membership and deployment settings.

## Help and Privacy

- Help: <https://yorihito.github.io/symmetrical-carnival/>
- English help: <https://yorihito.github.io/symmetrical-carnival/en/>
- Privacy policy: <https://yorihito.github.io/symmetrical-carnival/privacy.html>

Problem reports can be submitted from Settings. When the report proxy is not
configured, the app falls back to opening a prefilled public GitHub Issue.
Do not include information you do not want published publicly.

The Worker deployment procedure is documented in
[server/README.md](server/README.md).

## Documentation

- [Current repository overview](docs/repository-overview.md)
- [Product requirements and implementation status](REQUIREMENTS.md)
- [App launch/playbook alignment](docs/playbook-alignment.md)
- [App Review notes](docs/AppStore/ReviewNotes.md)
- [macOS App Store metadata](docs/AppStore/Metadata_Mac.md)
- [iOS App Store metadata](docs/AppStore/Metadata_iOS.md)

## License

Copyright © 2026 Yorihito Tada. Licensed under the [MIT License](LICENSE).

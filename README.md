# Denon Controller

**Stop searching for the remote. Control your Denon/Marantz system with the fastest, most responsive app ever made.**

Denon Controller is a premium, lightweight, and ultra-responsive remote control application for Denon and Marantz AV Receivers (AVR). Built with a focus on user experience and speed, it eliminates the lag and complexity of traditional apps, giving you instant command over your home theater.

## 📱 User Experience

- **Lightning-Fast Response:** Experience zero-friction control. Whether you're adjusting volume or switching inputs, the receiver responds instantly.
- **Tactile Feedback:** Feel every interaction. On iOS, we use the Taptic Engine to provide satisfying haptic confirmation for button presses and volume adjustments.
- **Modern Design:** A clean, focused interface that looks beautiful on any device and stays out of your way while you enjoy your media.

## 🚀 Platform Support

- **iOS & iPadOS:** A native mobile experience designed for one-handed use on iPhone and full productivity with Split View/Stage Manager on iPad.
- **macOS Menu Bar:** Control your audio system without leaving your current app. A dedicated macOS client lives in your Menu Bar for instant access to power, volume, and input controls.

## 🛠 Key Features

- **Power & Volume:** Effortless management of main and secondary zones.
- **Multi-Zone Support:** Full control over Zone 2 and Zone 3 power and volume levels.
- **Input & Surround:** Quick-switch between HDMI, Phono, Bluetooth, and more, or change your Surround Mode on the fly.
- **Tuner Management:** Manage FM/AM frequencies and bulk-fetch presets directly from your AVR.
- **Auto-Discovery:** Automatically finds your AVR on the network using mDNS (Bonjour) technology.

## 💻 Technology Stack

- **Swift 6 / SwiftUI:** Leveraging the latest language features and declarative UI framework.
- **Observation Framework:** Modern state management for reactive UI updates.
- **Denon HTTP API:** High-speed communication via the network-enabled HTTP API (Port 8080).
- **mDNS/Bonjour:** Seamless device discovery without needing to remember IP addresses.

## 🏗 Setup & Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ytada/symmetrical-carnival.git
   ```
2. **Open the project:**
   Open `DenonController/DenonController.xcodeproj` in Xcode 15 or later.
3. **Select your target:**
   - Choose `DenonController` for the macOS Menu Bar app.
   - Choose `DenonControllerMobile` for the iOS/iPadOS app.
4. **Build and Run:**
   Ensure your device is on the same Wi-Fi network as your AVR.

## ⚖️ Compatibility

Requires a network-enabled Denon or Marantz AV Receiver that supports the HTTP API (Port 8080). 
*Compatible with most HEOS-ready models, including the AVR-X3800H and similar series.*

---

**Copyright (c) 2026 Yorihito Tada. All rights reserved.**

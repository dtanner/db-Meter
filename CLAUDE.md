# CLAUDE.md

## Project Overview

dB Meter is a native macOS menu bar app that shows real-time sound pressure level (SPL) in decibels from the system's audio input device.

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Audio**: AVFoundation (AVAudioEngine for audio capture and level metering)
- **Target**: macOS 14.0+ (Sonoma)
- **Build System**: Xcode project (.xcodeproj)

## Architecture

- **Menu bar app** with a popover showing the dB level, plus an optional detachable window
- **Audio input selection**: defaults to the system input device, with a picker to switch between available devices
- **Live display only**: no history, graphs, or logging — just the current dB reading and a visual meter
- The app does NOT use the App Store; it's open source and distributed as a `.dmg` or built from source
- No paid Apple Developer account — uses personal team signing

## Key Frameworks and APIs

- `AVAudioEngine` — captures audio from the input device
- `AVAudioInputNode` — taps the microphone input
- `installTap(onBus:bufferSize:format:)` — reads audio buffers to calculate RMS and convert to dB
- `NSStatusBar` / `NSStatusItem` — menu bar presence
- `NSPopover` — menu bar popover UI
- `AVCaptureDevice.DiscoverySession` or `AVAudioSession` — enumerate available input devices

## Build and Run

```
open "dB Meter.xcodeproj"
# Build and run with Cmd+R in Xcode
```

Or from the command line:
```
xcodebuild -project "dB Meter.xcodeproj" -scheme "dB Meter" -configuration Release build
```

## Project Conventions

- Use SwiftUI for all UI code
- Follow standard Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Keep the app lightweight — no third-party dependencies
- Minimum deployment target: macOS 14.0

## Entitlements

The app requires:
- `com.apple.security.device.audio-input` — microphone access

## File Structure (planned)

```
dB Meter/
├── dBMeterApp.swift          # App entry point, menu bar setup
├── ContentView.swift         # Main meter display view
├── AudioManager.swift        # AVAudioEngine setup, dB calculation
├── DevicePicker.swift        # Audio input device selection UI
├── MenuBarController.swift   # NSStatusItem and popover management
└── Assets.xcassets/          # App icon and colors
```

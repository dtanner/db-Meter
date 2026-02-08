# dB Meter

A native macOS app that displays the current sound pressure level (SPL) from your microphone input in real time.

## Features

- Real-time decibel (dB) meter showing current sound pressure level
- Menu bar presence with a popover for quick glance at levels
- Optional detachable window for a larger view
- Select from available audio input devices or use the system default
- Built with Swift and SwiftUI for a native macOS experience

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15 or later (to build from source)
- A microphone or audio input device

## Building from Source

1. Clone the repository:
   ```
   git clone https://github.com/dtanner/spl.git
   cd spl
   ```

2. Open the Xcode project:
   ```
   open "dB Meter.xcodeproj"
   ```

3. Select your signing team in Xcode (your personal Apple ID works, no paid developer account needed):
   - Select the project in the navigator
   - Go to Signing & Capabilities
   - Choose your personal team

4. Build and run with `Cmd+R`, or build a release with `Product > Archive`.

## Installing a Pre-built Release

Download the latest `.dmg` from the [Releases](https://github.com/dtanner/spl/releases) page and drag `dB Meter.app` to your Applications folder.

Since the app is not notarized with an Apple Developer account, you may need to right-click the app and select "Open" the first time you run it, then confirm you want to open it.

## Permissions

The app requires microphone access. macOS will prompt you to grant permission the first time you run it.

## How It Works

dB Meter uses Apple's AVFoundation framework to capture audio from the selected input device and calculates the sound pressure level in decibels. The level is displayed as both a numeric dB reading and a visual meter.

## License

MIT

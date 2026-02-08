import SwiftUI

@main
struct dBMeterApp: App {
    @StateObject private var audioManager = AudioManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(audioManager: audioManager)
                .frame(width: 280, height: 200)
        } label: {
            Text(formatMenuBarLabel(audioManager.currentDB))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }

    private func formatMenuBarLabel(_ db: Float) -> String {
        if db.isFinite && db > -Float.infinity {
            return String(format: "%.0f dB", db)
        }
        return "-- dB"
    }
}

import SwiftUI

@main
struct dBMeterApp: App {
    @StateObject private var audioManager = AudioManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            Button("Show Meter") {
                openWindow(id: "meter")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Text(formatMenuBarLabel(audioManager.currentDB))
                .monospacedDigit()
        }

        Window("dB Meter", id: "meter") {
            ContentView(audioManager: audioManager)
                .frame(width: 280, height: 200)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private func formatMenuBarLabel(_ db: Float) -> String {
        if db.isFinite && db > -Float.infinity {
            return String(format: "%.0f dB", db)
        }
        return "-- dB"
    }
}

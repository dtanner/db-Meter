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

        Window("dB(A) Meter", id: "meter") {
            ContentView(audioManager: audioManager)
                .frame(minWidth: 240, minHeight: 240)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 320, height: 320)
        .defaultPosition(.center)
    }

    private func formatMenuBarLabel(_ db: Float) -> String {
        if db.isFinite && db > 0 {
            return String(format: "%.0f dB(A)", db)
        }
        return "-- dB(A)"
    }
}

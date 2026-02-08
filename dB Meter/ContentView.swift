import SwiftUI

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 12) {
            // dB Reading
            Text(formattedDB)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(dbColor)

            Text("dB SPL")
                .font(.caption)
                .foregroundColor(.secondary)

            // Level meter bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterGradient)
                        .frame(width: meterWidth(in: geometry.size.width))
                        .animation(.easeOut(duration: 0.1), value: audioManager.currentDB)
                }
            }
            .frame(height: 12)

            // Device picker
            DevicePicker(audioManager: audioManager)
        }
        .padding()
    }

    private var formattedDB: String {
        let db = audioManager.currentDB
        if db.isFinite && db > -96 {
            return String(format: "%.1f", db)
        }
        return "--"
    }

    private var dbColor: Color {
        let db = audioManager.currentDB
        if db > -6 { return .red }
        if db > -20 { return .yellow }
        return .green
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func meterWidth(in totalWidth: CGFloat) -> CGFloat {
        let db = audioManager.currentDB
        guard db.isFinite else { return 0 }
        // Map -96...0 dB to 0...1
        let normalized = CGFloat((db + 96) / 96)
        return max(0, min(1, normalized)) * totalWidth
    }
}

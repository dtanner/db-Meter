import SwiftUI

enum MeterTab: String, CaseIterable {
    case meter = "Meter"
    case history = "History"
    case settings = "Settings"
}

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var selectedTab: MeterTab = .meter

    var body: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $selectedTab) {
                ForEach(MeterTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedTab {
            case .meter:
                meterView
            case .history:
                HistoryChartView(audioManager: audioManager)
            case .settings:
                settingsView
            }

            DevicePicker(audioManager: audioManager)
        }
        .padding()
    }

    private var meterView: some View {
        VStack(spacing: 12) {
            // dB Reading
            Text(formattedDB)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(dbColor)

            Text("dB(A) SPL")
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
        }
    }

    private var settingsView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calibration Offset")
                    .font(.headline)

                HStack {
                    Text("\(Int(audioManager.calibrationOffset)) dB")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                    Slider(value: $audioManager.calibrationOffset, in: 60...130, step: 1)
                }

                Text("Adjusts the dBFS-to-dB(A) SPL conversion. Calibrate with a known reference source for accuracy.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset to Default") {
                    audioManager.calibrationOffset = AudioManager.defaultCalibrationOffset
                }
                .font(.caption)
            }

            Spacer()
        }
    }

    private var formattedDB: String {
        let db = audioManager.currentDB
        if db.isFinite && db > 0 {
            return String(format: "%.0f", db)
        }
        return "--"
    }

    private var dbColor: Color {
        let db = audioManager.currentDB
        if db > 85 { return .red }
        if db > 70 { return .yellow }
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
        // Map 0...130 dB(A) SPL to 0...1
        let normalized = CGFloat(db / 130)
        return max(0, min(1, normalized)) * totalWidth
    }
}

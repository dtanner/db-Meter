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

}
